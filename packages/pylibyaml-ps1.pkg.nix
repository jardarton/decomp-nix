{ fetchPypi, python3Packages }:
python3Packages.buildPythonPackage {
  pname = "pylibyaml";
  version = "0.1.0";
  pyproject = true;
  src = fetchPypi {
    pname = "pylibyaml";
    version = "0.1.0";
    hash = "sha256-O1jeoGGQPARonjX6tj7BSffPXoLwgIvTQl+zqzlQYj4=";
  };
  build-system = [ python3Packages.setuptools ];
}
