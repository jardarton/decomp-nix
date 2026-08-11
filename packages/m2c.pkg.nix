{
  fetchFromGitHub,
  graphviz,
  lib,
  python312Packages,
}:
python312Packages.buildPythonApplication rec {
  pname = "m2c";
  version = "0.1.0-unstable-2026-08-11";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "matt-kempster";
    repo = "m2c";
    rev = "10deabd76346bb59cf02a4e04d02b106dd60cce4";
    hash = "sha256-c53IesADvwW/wD69zGDCAZPf7Oyne/jXqLypx+UQEyA=";
  };

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'graphviz ~= 0.20.1' 'graphviz >= 0.20.1'
  '';

  build-system = [ python312Packages.poetry-core ];
  dependencies = [ python312Packages.graphviz ];

  makeWrapperArgs = [ "--prefix PATH : ${lib.makeBinPath [ graphviz ]}" ];

  nativeCheckInputs = [ python312Packages.coverage ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck

    export HOME="$TMPDIR"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    python run_tests.py --parallel "$NIX_BUILD_CORES"
    (cd m2c_pycparser && python -m unittest discover -v tests)

    $out/bin/m2c --help | grep -F "Decompile assembly to C."

    smoke="$TMPDIR/m2c-smoke"
    mkdir -p "$smoke"
    cd "$smoke"
    cat > smoke.s <<'ASM'
    glabel smoke
       addiu   v0,a0,1
       jr      ra
        nop
    ASM

    $out/bin/m2c --target mipsel-gcc-c --function smoke smoke.s > smoke.c
    grep -F "smoke(" smoke.c
    grep -F "arg0 + 1" smoke.c

    $out/bin/m2c --target mipsel-gcc-c --function smoke --visualize=c smoke.s > smoke.svg
    grep -F '<svg' smoke.svg
    grep -F 'arg0' smoke.svg

    runHook postCheck
  '';

  pythonImportsCheck = [
    "graphviz"
    "m2c"
    "m2c_pycparser"
  ];

  meta = {
    description = "Decompiler for 32-bit MIPS, ARM, PowerPC, and SuperH assembly";
    homepage = "https://github.com/matt-kempster/m2c";
    license = lib.licenses.gpl3Only;
    mainProgram = "m2c";
    platforms = lib.platforms.unix;
  };
}
