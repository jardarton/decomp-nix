{
  fetchPypi,
  lib,
  python312Packages,
}:
let
  py = python312Packages;

  rabbitizer = py.buildPythonPackage rec {
    pname = "rabbitizer";
    version = "1.16.2";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-KbYkVzu1fzKH60qI8Y5dr1YW8isZIw9sdaeuMoPN0Eg=";
    };

    build-system = [ py.setuptools ];
    pythonImportsCheck = [ "rabbitizer" ];
  };
in
py.buildPythonPackage rec {
  pname = "spimdisasm";
  version = "1.42.4";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-CiyNtUYVImKIt/bIbtzIRKZU35YyFXL6i441Zn4bkD8=";
  };

  build-system = [
    py.setuptools
    py.twine
    py.wheel
  ];

  dependencies = [ rabbitizer ];
  pythonImportsCheck = [
    "rabbitizer"
    "spimdisasm"
  ];

  passthru = { inherit rabbitizer; };

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    $out/bin/spimdisasm --version | grep -F "spimdisasm ${version}"
    $out/bin/spimdisasm --help | grep -F singleFileDisasm
    $out/bin/disasmdis --help | grep -F instr-category
    $out/bin/singleFileDisasm --help | grep -F instr-category

    actual=$($out/bin/disasmdis --instr-category r3000gte 00000000 24020001)
    printf '%s\n' "$actual" | grep -Fx nop
    printf '%s\n' "$actual" | grep -F 'addiu' | grep -F '$v0, $zero, 0x1'

    runHook postInstallCheck
  '';

  meta = {
    description = "MIPS and RSP disassembler supporting N64, PS1, PS2, PSP, and more";
    homepage = "https://github.com/Decompollaborate/spimdisasm";
    license = lib.licenses.mit;
    mainProgram = "spimdisasm";
    platforms = lib.platforms.unix;
  };
}
