{ pkgs }:

let
  spimdisasm = pkgs.callPackage ./spimdisasm.pkg.nix { };
  rabbitizer = spimdisasm.passthru.rabbitizer;
  splat64 = pkgs.callPackage ./splat64.pkg.nix { inherit spimdisasm; };
  splat = splat64;
  decompPythonEnv = pkgs.python312.withPackages (_: [
    rabbitizer
    spimdisasm
    (pkgs.python312Packages.toPythonModule splat)
  ]);
in
rec {
  asm-differ = pkgs.callPackage ./asm-differ.pkg.nix { };
  decomp-permuter = pkgs.callPackage ./decomp-permuter.pkg.nix { };
  ghidra-psx = pkgs.callPackage ./ghidra-psx.pkg.nix { };
  m2c = pkgs.callPackage ./m2c.pkg.nix { };
  # Separate authenticated PS1 pins from the general tool collection.
  m2c-10deabd = pkgs.callPackage ./m2c-10deabd.pkg.nix { };
  rabbitizer-ps1 = pkgs.callPackage ./rabbitizer-ps1.pkg.nix { };
  spimdisasm-ps1 = pkgs.callPackage ./spimdisasm-ps1.pkg.nix { rabbitizer = rabbitizer-ps1; };
  pylibyaml-ps1 = pkgs.callPackage ./pylibyaml-ps1.pkg.nix { };
  splat-ps1 = pkgs.callPackage ./splat-ps1.pkg.nix {
    rabbitizer = rabbitizer-ps1;
    spimdisasm = spimdisasm-ps1;
    pylibyaml = pylibyaml-ps1;
  };
  psyq-cc1-2_8_1-binary = pkgs.callPackage ./psyq-cc1-2_8_1-binary.pkg.nix { };
  psyq-cc1-2_8_1 = psyq-cc1-2_8_1-binary.command;
  psyq-cc1-2_7_2-al1_1-binary = pkgs.callPackage ./psyq-cc1-2_7_2-al1_1-binary.pkg.nix { };
  psyq-cc1-2_7_2-al1_1 = psyq-cc1-2_7_2-al1_1-binary.command;
  maspsx = pkgs.callPackage ./maspsx.pkg.nix { };
  psx-psyq-signatures = pkgs.callPackage ./psx-psyq-signatures.pkg.nix { };
  mkpsxiso = pkgs.callPackage ./mkpsxiso.pkg.nix { };
  pcsx-redux = pkgs.callPackage ./pcsx-redux.pkg.nix { };
  psyq-obj-parser = pkgs.callPackage ./psyq-obj-parser.pkg.nix { };
  inherit
    rabbitizer
    spimdisasm
    splat
    splat64
    ;

  ps1-decomp-tools = pkgs.buildEnv {
    name = "ps1-decomp-tools";
    paths = [
      asm-differ
      decomp-permuter
      ghidra-psx
      m2c
      maspsx
      mkpsxiso
      pcsx-redux
      psyq-obj-parser
      decompPythonEnv
    ];
  };

  default = ps1-decomp-tools;
}
