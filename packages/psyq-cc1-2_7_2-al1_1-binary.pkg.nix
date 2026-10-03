{
  callPackage,
  fetchurl,
  stdenvNoCC,
}:
let
  binary = stdenvNoCC.mkDerivation {
    pname = "psyq-gcc-cc1";
    version = "2.7.2-al1.1-hercules-candidate";
    src = fetchurl {
      url = "https://raw.githubusercontent.com/MediEvilDecompilation/medievil-decomp/6afe6fe35d5ddf0ce1bebdb2e72f8215b5b5b407/bin/cc1-2.7.2";
      hash = "sha256-cA7yH5IHuw+L+HsF8u/A1ifPbQF7KD8mkVtrA4yuJwg=";
    };
    dontUnpack = true;
    installPhase = "install -Dm755 $src $out/bin/psyq-cc1-2.7.2-al1.1";
    passthru.command = callPackage ./psyq-cc1-command.nix {
      inherit binary;
      executable = "psyq-cc1-2.7.2-al1.1";
    };
  };
in
binary
