{
  fetchPypi,
  lib,
  python312Packages,
  rustPlatform,
  spimdisasm,
}:
let
  py = python312Packages;

  pygfxd = py.buildPythonPackage rec {
    pname = "pygfxd";
    version = "1.0.5";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-sx9fhi3MwuD6pgXMFs1joi/rMkTAeiBjA3Qh/NP2cUU=";
    };

    build-system = [ py.setuptools ];
    pythonImportsCheck = [ "pygfxd" ];
  };

  n64img = py.buildPythonPackage rec {
    pname = "n64img";
    version = "0.3.3";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-SIs3kW60qUMjHq9JzpBS99b5b3yQcS7zrqqu9J47vxI=";
    };

    build-system = [ py.setuptools ];
    dependencies = [ py.pypng ];
    pythonImportsCheck = [ "n64img" ];
  };

  crunch64 = py.buildPythonPackage rec {
    pname = "crunch64";
    version = "0.6.2";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-zMrtEtYRc8F96WMMUfWCXGe+Fx/7ptcUhS1rZp9nphE=";
    };

    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit pname version src;
      hash = "sha256-mI6ydUTrfyO6xOdhMAaKyWS6OIp0OuZdkP4BzvcFRJE=";
    };

    nativeBuildInputs = [
      rustPlatform.cargoSetupHook
      rustPlatform.maturinBuildHook
    ];

    pythonImportsCheck = [ "crunch64" ];
  };

  pylibyaml = py.buildPythonPackage rec {
    pname = "pylibyaml";
    version = "0.1.0";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-O1jeoGGQPARonjX6tj7BSffPXoLwgIvTQl+zqzlQYj4=";
    };

    build-system = [ py.setuptools ];
    dependencies = [ py.pyyaml ];
    pythonImportsCheck = [ "pylibyaml" ];
  };

  intervaltree = py.buildPythonPackage rec {
    pname = "intervaltree";
    version = "3.1.0";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-kCsbiJNpGPmyoZ4OXrfMtDCuRc3k856ks2kykg0zlS0=";
    };

    build-system = [ py.setuptools ];
    dependencies = [ py.sortedcontainers ];
    pythonImportsCheck = [ "intervaltree" ];
  };

  tqdm = py.buildPythonPackage rec {
    pname = "tqdm";
    version = "4.67.1";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-+K75xSwIwTpl8w6jT05arD/Ro0lZh51+WeYwJyhmJ/I=";
    };

    build-system = [ py.setuptools-scm ];
    pythonImportsCheck = [ "tqdm" ];
  };
in
py.buildPythonApplication rec {
  pname = "splat64";
  version = "0.50.0";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-9TvDo/7NG3oBNnUJvs51ScWOjLmEmASr2eDzD34Vywo=";
  };

  build-system = [ py.hatchling ];

  dependencies = [
    crunch64
    n64img
    pygfxd
    spimdisasm
    intervaltree
    py.colorama
    pylibyaml
    py.pyyaml
    tqdm
  ];

  pythonImportsCheck = [
    "splat"
    "spimdisasm"
    "rabbitizer"
  ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    $out/bin/splat --version | grep -F "splat ${version}"
    $out/bin/splat --help | grep -F create_config

    workdir=$(mktemp -d)
    cd "$workdir"
    ${py.python.interpreter} - <<'PY'
    import struct

    image = bytearray(0x900)
    image[:8] = b"PS-X EXE"
    struct.pack_into("<IIII", image, 0x10, 0x80010000, 0, 0x80010000, 0x100)

    # Valid R3000 instructions make create_config exercise Rabbitizer's MIPS
    # decoder while identifying the text region in this synthetic PS-X EXE.
    words = [0x24020001, 0x24420001, 0x00431021, 0x10400001, 0x00000000]
    for index in range(64):
        struct.pack_into("<I", image, 0x800 + index * 4, words[index % len(words)])

    with open("smoke.exe", "wb") as exe:
        exe.write(image)
    PY
    $out/bin/splat create_config smoke.exe
    grep -F "platform: psx" smoke.exe.yaml

    runHook postInstallCheck
  '';

  meta = {
    description = "Binary splitting tool for decompilation and modding projects";
    homepage = "https://github.com/ethteck/splat";
    license = lib.licenses.mit;
    mainProgram = "splat";
    platforms = lib.platforms.unix;
  };
}
