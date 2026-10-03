{
  fetchPypi,
  python3Packages,
  rabbitizer,
}:
python3Packages.buildPythonPackage {
  pname = "spimdisasm";
  version = "1.42.4";
  pyproject = true;
  src = fetchPypi {
    pname = "spimdisasm";
    version = "1.42.4";
    hash = "sha256-CiyNtUYVImKIt/bIbtzIRKZU35YyFXL6i441Zn4bkD8=";
  };
  build-system = with python3Packages; [
    setuptools
    twine
    wheel
  ];
  dependencies = [ rabbitizer ];
}
