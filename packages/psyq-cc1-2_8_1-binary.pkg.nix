{
  callPackage,
  fetchurl,
  stdenvNoCC,
}:
let
  binary = stdenvNoCC.mkDerivation {
    pname = "psyq-gcc-cc1";
    version = "2.8.1-medievil-candidate";
    src = fetchurl {
      url = "https://raw.githubusercontent.com/MediEvilDecompilation/medievil-decomp/6afe6fe35d5ddf0ce1bebdb2e72f8215b5b5b407/bin/cc1-2.8.1";
      hash = "sha256-RO/csPoawBSbOgVvwbE9OeFO01UUviHCiXfgKGvq39o=";
    };
    dontUnpack = true;
    installPhase = "install -Dm755 $src $out/bin/psyq-cc1-2.8.1";
    passthru.command = callPackage ./psyq-cc1-command.nix {
      inherit binary;
      executable = "psyq-cc1-2.8.1";
    };
  };
in
binary
