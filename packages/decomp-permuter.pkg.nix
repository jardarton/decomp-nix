{
  fetchFromGitHub,
  lib,
  makeWrapper,
  pkgsCross,
  python312,
  stdenv,
  stdenvNoCC,
}:
let
  python = python312.withPackages (pythonPackages: [
    pythonPackages.levenshtein
    pythonPackages.pynacl
    pythonPackages.toml
  ]);
  cppProvider = stdenv.cc.cc;
  mipsToolchain = pkgsCross.mipsel-linux-gnu;
  mipsPrefix = mipsToolchain.stdenv.cc.targetPrefix;
in
stdenvNoCC.mkDerivation {
  pname = "decomp-permuter";
  version = "unstable-2026-09-07";

  src = fetchFromGitHub {
    owner = "simonlindholm";
    repo = "decomp-permuter";
    rev = "059609d4aec73eb0650726772954e1ad575825f8";
    hash = "sha256-Eed8H2d0lr+nTE3P49fwM6IpyJZjsJrsY4Bzn0t4zy4=";
  };

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    mipsToolchain.buildPackages.binutils
    mipsToolchain.stdenv.cc
    cppProvider
    python
  ];

  dontBuild = true;

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    export HOME="$TMPDIR"
    export XDG_CACHE_HOME="$TMPDIR/cache"

    # Upstream's fixture uses Debian's tool names. Point those names at the
    # pinned nixpkgs cross toolchain without modifying the tests themselves.
    testTools="$TMPDIR/test-tools"
    mkdir -p "$testTools"
    ln -s ${mipsToolchain.stdenv.cc}/bin/${mipsPrefix}gcc \
      "$testTools/mips-linux-gnu-gcc"
    ln -s ${mipsToolchain.buildPackages.binutils}/bin/${mipsPrefix}objdump \
      "$testTools/mips-linux-gnu-objdump"
    export PATH="$testTools:$PATH"

    patchShebangs run-tests.sh test/compile.sh
    ./run-tests.sh
    (cd perm_pycparser && ${python}/bin/python - <<'PY'
    import sys
    import unittest

    # The vendored parser retains five pycparser tests but not the C fixture
    # files those tests consume. Run every test that is complete in this tree.
    missing_fixture_tests = {
        "test_c_parser.TestCParser_whole_code.test_whole_file",
        "test_c_parser.TestCParser_whole_code.test_whole_file_with_stdio",
        "test_general.TestParsing.test_c11_with_cpp",
        "test_general.TestParsing.test_with_cpp",
        "test_general.TestParsing.test_without_cpp",
    }

    def flatten(suite):
        for test in suite:
            if isinstance(test, unittest.TestSuite):
                yield from flatten(test)
            else:
                yield test

    discovered = unittest.defaultTestLoader.discover("tests")
    tests = list(flatten(discovered))
    skipped = {test.id() for test in tests} & missing_fixture_tests
    if skipped != missing_fixture_tests:
        raise AssertionError(f"unexpected parser test set: {skipped!r}")
    print(
        "Skipping 5 vendored parser tests whose C fixtures are absent upstream:",
        ", ".join(sorted(skipped)),
    )
    runnable = unittest.TestSuite(
        test for test in tests if test.id() not in missing_fixture_tests
    )
    result = unittest.TextTestRunner(verbosity=2).run(runnable)
    sys.exit(not result.wasSuccessful())
    PY
    )

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    appDir="$out/share/decomp-permuter"
    mkdir -p \
      "$appDir/src/net" \
      "$appDir/src/perm" \
      "$appDir/perm_pycparser/ply" \
      "$out/bin"

    install -Dm644 permuter.py import.py -t "$appDir"
    install -Dm644 \
      default_weights.toml \
      example_settings.toml \
      permuter_settings_example.toml \
      prelude.inc \
      -t "$appDir"
    install -Dm644 LICENSE README.md USAGE.md -t "$appDir"

    find src -maxdepth 1 -type f -name '*.py' \
      -exec install -Dm644 {} "$appDir/src/" \;
    find src/perm -maxdepth 1 -type f -name '*.py' \
      -exec install -Dm644 {} "$appDir/src/perm/" \;
    install -Dm644 \
      src/net/__init__.py \
      src/net/client.py \
      src/net/core.py \
      src/net/evaluator.py \
      -t "$appDir/src/net"

    for file in \
      __init__.py \
      ast_transforms.py \
      c_ast.py \
      c_generator.py \
      c_lexer.py \
      c_parser.py \
      lextab.py \
      plyparser.py \
      yacctab.py \
      _c_ast.cfg \
      LICENSE \
      README
    do
      install -Dm644 "perm_pycparser/$file" "$appDir/perm_pycparser/$file"
    done
    find perm_pycparser/ply -maxdepth 1 -type f \
      \( -name '*.py' -o -name LICENSE \) \
      -exec install -Dm644 {} "$appDir/perm_pycparser/ply/" \;

    makeWrapper ${python}/bin/python "$out/bin/decomp-permuter" \
      --add-flags "$appDir/permuter.py" \
      --set PYTHONDONTWRITEBYTECODE 1 \
      --prefix PATH : ${lib.makeBinPath [ cppProvider ]}
    makeWrapper ${python}/bin/python "$out/bin/decomp-permuter-import" \
      --add-flags "$appDir/import.py" \
      --set PYTHONDONTWRITEBYTECODE 1 \
      --prefix PATH : ${lib.makeBinPath [ cppProvider ]}

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME="$TMPDIR"
    export PYTHONDONTWRITEBYTECODE=1
    export XDG_CACHE_HOME="$TMPDIR/cache"
    smoke="$TMPDIR/decomp-permuter-smoke"
    mkdir -p "$smoke/input"
    cd "$smoke"

    $out/bin/decomp-permuter --help | grep -F "directories"
    $out/bin/decomp-permuter-import --help | grep -F "Import a function"
    PYTHONPATH="$out/share/decomp-permuter" ${python}/bin/python -c \
      'import src.net.client, src.net.core, src.net.evaluator'

    cat > input/base.c <<'C'
    int smoke(int arg0) {
        return PERM_GENERAL(1, 2);
    }
    C
    cat > input/settings.toml <<EOF
    compiler_type = "base"
    objdump_command = "$smoke/fake-objdump"
    func_name = "smoke"
    EOF

    cat > input/compile.sh <<EOF
    #!/bin/sh
    set -eu
    input=\$1
    shift
    test "\$1" = -o
    output=\$2
    printf 'compile %s\\n' "\$input" >> "$smoke/compile.log"
    ${python}/bin/python - "\$input" "\$output" <<'PY'
    import pathlib
    import sys

    source = pathlib.Path(sys.argv[1]).read_text()
    header = bytearray(20)
    header[0:4] = b"\\x7fELF"
    header[5] = 1
    header[18] = 8  # EM_MIPS, little-endian
    pathlib.Path(sys.argv[2]).write_bytes(header + source.encode())
    PY
    EOF
    chmod +x input/compile.sh

    cat > fake-objdump <<EOF
    #!/bin/sh
    set -eu
    object=\$1
    printf 'objdump %s\\n' "\$object" >> "$smoke/objdump.log"
    if grep -a -q 'return 2' "\$object"; then
      immediate=2
    else
      immediate=1
    fi
    printf 'fixture.o: file format elf32-littlemips\\n'
    printf '00000000 <smoke>:\\n'
    printf '   0:\\t24820000 \\taddiu\\tv0,a0,%s\\n' "\$immediate"
    printf '   4:\\t03e00008 \\tjr\\tra\\n'
    printf '   8:\\t00000000 \\tnop\\n'
    EOF
    chmod +x fake-objdump

    ${python}/bin/python - <<'PY'
    import pathlib

    header = bytearray(20)
    header[0:4] = b"\x7fELF"
    header[5] = 1
    header[18] = 8
    pathlib.Path("input/target.o").write_bytes(header + b"return 2")
    PY

    $out/bin/decomp-permuter --stop-on-zero --seed 1,1 input | tee smoke.log
    grep -F "Found zero score" smoke.log
    grep -F "compile " compile.log
    grep -F "objdump " objdump.log

    importProject="$smoke/import-project"
    mkdir -p "$importProject"
    cat > "$importProject/source.c" <<'C'
    #define PACKAGED_CPP_VALUE 37
    int imported(void) {
        return PERM_GENERAL(PACKAGED_CPP_VALUE, 38);
    }
    C
    cat > "$importProject/target.s" <<'ASM'
    glabel imported
       jr      ra
        nop
    ASM
    cat > "$importProject/fake-compiler" <<EOF
    #!${stdenv.shell}
    set -eu
    input=\$1
    shift
    test "\$1" = -o
    output=\$2
    printf 'compiler %s\\n' "\$input" >> "$smoke/import-tools.log"
    cp "\$input" "\$output"
    EOF
    cat > "$importProject/fake-assembler" <<EOF
    #!${stdenv.shell}
    set -eu
    input=\$1
    shift
    test "\$1" = -o
    output=\$2
    printf 'assembler %s\\n' "\$input" >> "$smoke/import-tools.log"
    cp "\$input" "\$output"
    EOF
    chmod +x "$importProject/fake-compiler" "$importProject/fake-assembler"
    cat > "$importProject/permuter_settings.toml" <<EOF
    compiler_type = "base"
    compiler_command = "$importProject/fake-compiler"
    assembler_command = "$importProject/fake-assembler"
    EOF

    mkdir -p "$smoke/ambient-bin"
    cat > "$smoke/ambient-bin/cpp" <<EOF
    #!${stdenv.shell}
    touch "$smoke/ambient-cpp-used"
    exit 99
    EOF
    chmod +x "$smoke/ambient-bin/cpp"

    PATH="$smoke/ambient-bin:$PATH" \
      $out/bin/decomp-permuter-import \
      "$importProject/source.c" \
      "$importProject/target.s" | tee import.log
    test ! -e "$smoke/ambient-cpp-used"
    grep -F "Preserving no macros" import.log
    grep -F "PERM_GENERAL(37, 38)" nonmatchings/imported/base.c
    grep -F ".set noat" nonmatchings/imported/target.s
    grep -F "assembler " import-tools.log

    test -f "$out/share/decomp-permuter/default_weights.toml"
    test -f "$out/share/decomp-permuter/prelude.inc"
    test -f "$out/share/decomp-permuter/permuter_settings_example.toml"
    test -f "$out/share/decomp-permuter/example_settings.toml"
    test -f "$out/share/decomp-permuter/src/main.py"
    test -f "$out/share/decomp-permuter/perm_pycparser/c_parser.py"
    test -f "$out/share/decomp-permuter/LICENSE"
    test -f "$out/share/decomp-permuter/README.md"
    test -f "$out/share/decomp-permuter/USAGE.md"

    test -z "$(find "$out" -type d -name __pycache__ -print -quit)"
    test -z "$(find "$out" -type f -name '*.pyc' -print -quit)"
    test ! -e "$out/share/decomp-permuter/test"
    test ! -e "$out/share/decomp-permuter/perm_pycparser/tests"
    test ! -e "$out/share/decomp-permuter/stubs"
    test ! -e "$out/share/decomp-permuter/.github"
    test ! -e "$out/share/decomp-permuter/src/net/cmd"
    test ! -e "$out/share/decomp-permuter/src/net/cmd/systray/prebuilt"

    runHook postInstallCheck
  '';

  meta = {
    description = "C source permuter for matching decompilation projects";
    homepage = "https://github.com/simonlindholm/decomp-permuter";
    license = lib.licenses.mit;
    mainProgram = "decomp-permuter";
    platforms = lib.platforms.unix;
  };
}
