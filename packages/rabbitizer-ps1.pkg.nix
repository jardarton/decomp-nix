{ fetchPypi, python3Packages }:
python3Packages.buildPythonPackage {
  pname = "rabbitizer";
  version = "1.16.2";
  pyproject = true;
  src = fetchPypi {
    pname = "rabbitizer";
    version = "1.16.2";
    hash = "sha256-KbYkVzu1fzKH60qI8Y5dr1YW8isZIw9sdaeuMoPN0Eg=";
  };
  build-system = [ python3Packages.setuptools ];
}
