# decomp-nix

Reproducible Nix packages and development environments for matching
decompilation projects.

PS1 is the first fully supported platform. The repository is structured so
that additional console, platform, and architecture profiles can be added as
the package collection grows.

## Quick start

Run or temporarily install an individual tool directly from the repository:

```sh
nix run github:jardarton/decomp-nix#splat -- --help
nix shell github:jardarton/decomp-nix#maspsx
```

Enter a shell containing the complete PS1 toolset:

```sh
NIXPKGS_ALLOW_UNFREE=1 \
  nix develop --impure github:jardarton/decomp-nix#ps1
```

The unfree opt-in is required because `ghidra-psx` incorporates upstream
projects without repository-level license grants. To permit it persistently,
configure an appropriate `allowUnfree` or `allowUnfreePredicate` in your Nixpkgs
configuration.

## Packages

| Package | Purpose |
| --- | --- |
| `asm-differ` | Interactive assembly comparison for matching functions |
| `decomp-permuter` | Searches source-code permutations for better compiler matches |
| `ghidra-psx` | Ghidra with a PS-X EXE loader, GTE support, and PsyQ signatures |
| `m2c` | Converts MIPS and several other assembly languages into approximate C |
| `maspsx` | Reproduces PsyQ ASPSX preprocessing with a modern assembler |
| `mkpsxiso` | Creates and extracts PS1 BIN/CUE images; includes `dumpsxiso` |
| `pcsx-redux` | PS1 emulator with debugging, tracing, scripting, and OpenBIOS |
| `psyq-obj-parser` | Converts PsyQ LNK object files into ELF objects |
| `rabbitizer` | MIPS instruction decoder used by decompilation tooling |
| `spimdisasm` | MIPS and RSP disassembler for PS1, N64, PS2, PSP, and related targets |
| `splat` | Splits binaries into source, data, symbols, and linker configuration |

The `ps1-decomp-tools` package combines the complete PS1 toolset. Individual
packages remain available for projects that need smaller closures.

Package sources and dependencies are pinned by `flake.lock`. Builds contain
upstream tests and project-specific smoke tests where practical.

## Development shells

| Shell | Contents |
| --- | --- |
| `common` | Platform-independent matching tools |
| `mips` | Common tools plus MIPS analysis tools |
| `ps1` | Common, MIPS, and PS1-specific tools |
| `default` | Alias for the `ps1` shell |
| `development` | Nix formatting and linting tools for this repository |

For example:

```sh
nix develop .#common
nix develop .#mips
NIXPKGS_ALLOW_UNFREE=1 nix develop --impure .#ps1
nix develop .#development
```

## Use from another flake

The following complete `flake-parts` example adds selected tools to a project
development shell:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";

    decomp-nix = {
      url = "github:jardarton/decomp-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        { pkgs, system, ... }:
        let
          decomp = inputs.decomp-nix.packages.${system};
        in
        {
          devShells.default = pkgs.mkShell {
            packages = [
              decomp.asm-differ
              decomp.maspsx
              decomp.splat
            ];
          };
        };
    };
}
```

The flake also exports `overlays.default` for consumers that prefer a Nixpkgs
overlay.

## Supported hosts

The flake currently exposes packages and shells for:

- `x86_64-linux`
- `aarch64-linux`

These are host systems; the packaged tools can analyze binaries for other
architectures and platforms where documented.

## Contributing and updating packages

Keep package sources pinned, retain relevant upstream tests, and add a focused
smoke test when packaging behavior is not already covered. Do not add
proprietary SDK files, game data, or Sony disc license data.

Before submitting a change, run:

```sh
nix fmt
nix develop .#development -c deadnix --fail .
nix develop .#development -c statix check .
NIXPKGS_ALLOW_UNFREE=1 nix flake check --impure --all-systems --no-build
NIXPKGS_ALLOW_UNFREE=1 nix build --impure .#<changed-package>
```

Building a package executes the tests and smoke checks defined by its
derivation.

## Licensing

The Nix expressions and repository documentation are available under the MIT
license; see [`LICENSE`](LICENSE). Packaged software retains its own upstream
license. Consult each package's metadata and upstream project before
redistributing its output.

`ghidra-psx` is marked unfree because its extension and signature sources do
not provide repository-level license grants. This repository does not
distribute the proprietary PsyQ SDK or Sony disc license data.
