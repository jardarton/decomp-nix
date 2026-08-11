{ pkgs }:

let
  spimdisasm = pkgs.callPackage ./spimdisasm.pkg.nix { };
in
rec {
  asm-differ = pkgs.callPackage ./asm-differ.pkg.nix { };
  decomp-permuter = pkgs.callPackage ./decomp-permuter.pkg.nix { };
  ghidra-psx = pkgs.callPackage ./ghidra-psx.pkg.nix { };
  m2c = pkgs.callPackage ./m2c.pkg.nix { };
  maspsx = pkgs.callPackage ./maspsx.pkg.nix { };
  mkpsxiso = pkgs.callPackage ./mkpsxiso.pkg.nix { };
  pcsx-redux = pkgs.callPackage ./pcsx-redux.pkg.nix { };
  psyq-obj-parser = pkgs.callPackage ./psyq-obj-parser.pkg.nix { };
  rabbitizer = spimdisasm.passthru.rabbitizer;
  inherit spimdisasm;
  splat64 = pkgs.callPackage ./splat64.pkg.nix { inherit spimdisasm; };
  splat = splat64;

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
      spimdisasm
      splat
    ];
  };

  default = ps1-decomp-tools;
}
