{
  description = "Nix packages and development environments for matching decompilation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      flake.overlays.default = final: _prev: import ./packages { pkgs = final; };

      perSystem =
        { pkgs, ... }:
        let
          decompPackages = import ./packages { inherit pkgs; };
          commonPackages = with decompPackages; [
            asm-differ
            decomp-permuter
          ];
          mipsPackages =
            commonPackages
            ++ (with decompPackages; [
              m2c
              rabbitizer
              spimdisasm
              splat
            ]);
          ps1Packages =
            mipsPackages
            ++ (with decompPackages; [
              ghidra-psx
              maspsx
              mkpsxiso
              pcsx-redux
              psyq-obj-parser
            ]);
          ps1Shell = pkgs.mkShell { packages = ps1Packages; };
        in
        {
          packages = decompPackages;

          devShells = {
            common = pkgs.mkShell { packages = commonPackages; };
            mips = pkgs.mkShell { packages = mipsPackages; };
            ps1 = ps1Shell;
            default = ps1Shell;
            development = pkgs.mkShell {
              packages = [
                pkgs.deadnix
                pkgs.nixfmt
                pkgs.statix
              ];
            };
          };

          formatter = pkgs.nixfmt-tree;
        };
    };
}
