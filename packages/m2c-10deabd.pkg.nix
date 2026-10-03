{
  fetchFromGitHub,
  lib,
  python3Packages,
}:
python3Packages.buildPythonApplication {
  pname = "m2c";
  version = "0.1.0-10deabd";
  pyproject = true;
  src = fetchFromGitHub {
    owner = "matt-kempster";
    repo = "m2c";
    rev = "10deabd76346bb59cf02a4e04d02b106dd60cce4";
    hash = "sha256-c53IesADvwW/wD69zGDCAZPf7Oyne/jXqLypx+UQEyA=";
  };
  build-system = [ python3Packages.poetry-core ];
  dependencies = [ python3Packages.graphviz ];
  pythonRelaxDeps = [ "graphviz" ];
  meta = {
    description = "MIPS, ARM, PowerPC and SuperH decompiler";
    homepage = "https://github.com/matt-kempster/m2c";
    license = lib.licenses.gpl3Only;
    mainProgram = "m2c";
  };
}
