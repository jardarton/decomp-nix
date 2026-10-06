{
  fetchFromGitHub,
  file,
  lib,
  makeBinaryWrapper,
  makeWrapper,
  micropython,
  pkgsCross,
  python3,
  python313,
  stdenvNoCC,
}:
let
  mipsBinutils = pkgsCross.mips-embedded.buildPackages.binutils-unwrapped;
  mipsAssembler = "${mipsBinutils}/bin/${mipsBinutils.targetPrefix}as";

  # mpy-cross is built alongside MicroPython but not installed by nixpkgs.
  # MicroPython's test suite compares its output with CPython's; CPython 3.14
  # changed messages several tests expect (the PEP 765 SyntaxWarning, math
  # domain errors, a complex() DeprecationWarning), so compare with 3.13.
  micropython' = micropython.overrideAttrs (old: {
    env = (old.env or { }) // {
      MICROPY_CPYTHON3 = "${python313}/bin/python3";
    };
    postInstall = (old.postInstall or "") + ''
      install -Dm755 mpy-cross/build/mpy-cross -t "$out/bin"
    '';
  });

  micropythonSupport = ./maspsx-micropython;
in
stdenvNoCC.mkDerivation {
  pname = "maspsx";
  version = "unstable-2026-09-23";

  src = fetchFromGitHub {
    owner = "mkst";
    repo = "maspsx";
    rev = "7686f845a181700534c83c0419183e38aeb3e49c";
    hash = "sha256-Q6NDNesXDj79mBeM24h+RhSZQG5fo4JuVPexQVSqnIQ=";
  };

  postPatch = ''
    substituteInPlace maspsx.py \
      --replace-fail 'default="mipsel-linux-gnu-as"' 'default="${mipsAssembler}"'
  '';

  nativeBuildInputs = [
    makeBinaryWrapper
    makeWrapper
    micropython'
    python3
  ];
  nativeCheckInputs = [
    file
    mipsBinutils
    python3
  ];

  # Translate upstream maspsx for MicroPython and compile it to bytecode; see
  # maspsx-micropython/rewrite.py and runtime/maspsx_main.py.
  buildPhase = ''
    runHook preBuild

    mkdir -p micropython/maspsx micropython-bytecode/maspsx
    python3 ${micropythonSupport}/rewrite.py \
      maspsx/__init__.py micropython/maspsx/__init__.py \
      maspsx.py micropython/maspsx_cli.py
    cp ${micropythonSupport}/runtime/*.py micropython/
    substituteInPlace micropython/maspsx_main.py \
      --replace-fail '@cpython_maspsx@' "$out/bin/maspsx-cpython"
    (
      cd micropython
      for source in *.py maspsx/__init__.py; do
        mpy-cross -o "../micropython-bytecode/''${source%.py}.mpy" "$source"
      done
    )

    runHook postBuild
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    python -m unittest --verbose 2>&1 | tee unit-tests.log
    grep -F "Ran 151 tests" unit-tests.log
    grep -Fx "OK" unit-tests.log

    # Replay every processor run and regular expression from the unit tests,
    # and decimal strings for the float parser, on MicroPython.
    PYTHONPATH=. PYTHONDONTWRITEBYTECODE=1 python3 ${micropythonSupport}/tests/record.py \
      "$TMPDIR/processors.json" "$TMPDIR/regexes.json" "$TMPDIR/floats.json"
    MICROPYPATH="$PWD/micropython-bytecode" micropython -X heapsize=16M \
      ${micropythonSupport}/tests/replay.py \
      "$TMPDIR/processors.json" "$TMPDIR/regexes.json" "$TMPDIR/floats.json"

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    appDir="$out/share/maspsx"
    moduleDir="$appDir/maspsx"
    mkdir -p "$appDir" "$moduleDir" "$out/bin"
    install -Dm644 maspsx.py "$appDir/maspsx.py"
    install -Dm644 maspsx/__init__.py "$moduleDir/__init__.py"
    install -Dm644 LICENSE README.md -t "$appDir"
    mkdir -p "$out/${python3.sitePackages}"
    ln -s "$moduleDir" "$out/${python3.sitePackages}/maspsx"

    makeWrapper ${python3}/bin/python "$out/bin/maspsx-cpython" \
      --add-flags "$appDir/maspsx.py" \
      --set PYTHONDONTWRITEBYTECODE 1 \
      --prefix PYTHONPATH : "$out/${python3.sitePackages}"

    # A 16 MiB heap holds inputs of about 15,000 lines; larger ones run out of
    # memory and fall back to CPython.
    cp -r micropython-bytecode "$appDir/micropython"
    makeBinaryWrapper ${micropython'}/bin/micropython "$out/bin/maspsx" \
      --set MICROPYPATH "$appDir/micropython" \
      --add-flags "-X heapsize=16M -m maspsx_main"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    export HOME="$TMPDIR"
    export PYTHONDONTWRITEBYTECODE=1
    sourceDir="$PWD"
    cd "$TMPDIR"

    $out/bin/maspsx --help | grep -F -- "--run-assembler"
    PYTHONPATH="$out/${python3.sitePackages}" \
      ${python3}/bin/python -c 'from maspsx import MaspsxProcessor'

    cat > smoke.s <<'ASM'
    .text
    .set noreorder
    .globl smoke
    .ent smoke
    smoke:
        li      $2,0x12345678
        addu    $2,$2,$4
        jr      $31
        nop
    .end smoke
    ASM

    for maspsx in maspsx maspsx-cpython; do
      MASPSX_MICROPYTHON_NO_FALLBACK=1 $out/bin/$maspsx \
        --aspsx-version=2.81 \
        --run-assembler \
        -EL \
        -march=r3000 \
        -o $maspsx.o \
        < smoke.s

      test -s $maspsx.o
      ${file}/bin/file $maspsx.o | tee file.log
      grep -F "ELF 32-bit LSB relocatable, MIPS" file.log
      ${mipsBinutils}/bin/${mipsBinutils.targetPrefix}readelf -h $maspsx.o | tee readelf.log
      grep -F "Data:" readelf.log | grep -F "little endian"
      grep -F "Machine:" readelf.log | grep -F "MIPS R3000"
    done
    cmp maspsx.o maspsx-cpython.o

    # End-to-end comparison of both commands; see tests/cli_diff.py.
    python3 ${micropythonSupport}/tests/cli_diff.py \
      $out/bin/maspsx $out/bin/maspsx-cpython "$TMPDIR/processors.json" \
      "$sourceDir/aspsx/ASM"

    runHook postInstallCheck
  '';

  meta = {
    description = "Modern replacement for the PsyQ ASPSX assembly preprocessor";
    homepage = "https://github.com/mkst/maspsx";
    license = lib.licenses.mit;
    mainProgram = "maspsx";
    platforms = lib.platforms.linux;
  };
}
