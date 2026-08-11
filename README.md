# decomp-nix

Reproducible Nix packages and development environments for matching
decompilation projects.

PS1 is the first supported platform. Additional platform and architecture
profiles can be added as the package collection grows.

## Packages

- `asm-differ`
- `decomp-permuter`
- `ghidra-psx`
- `m2c`
- `maspsx`
- `mkpsxiso` (including `dumpsxiso`)
- `pcsx-redux`
- `psyq-obj-parser`
- `rabbitizer`
- `spimdisasm`
- `splat`

`ps1-decomp-tools` combines the PS1 toolset. Individual packages remain
available when a project needs a smaller environment.

## Development shells

```sh
nix develop               # PS1 toolset
nix develop .#common      # Platform-independent matching tools
nix develop .#mips        # Common and MIPS tools
nix develop .#ps1         # Common, MIPS, and PS1 tools
nix develop .#development # Nix repository maintenance tools
```

`ghidra-psx` combines Ghidra with upstream projects that do not provide a
repository-level license grant, so Nix treats the composition as unfree. Users
must explicitly permit unfree packages to use the complete PS1 shell.

This repository does not distribute the proprietary PsyQ SDK or Sony disc
license data.

## Flake use

```nix
{
  inputs.decomp-nix.url = "github:jardarton/decomp-nix";
}
```

Packages are available under `decomp-nix.packages.${system}`. The default
overlay is also exported for consumers that prefer overlays.

## Development

```sh
nix develop .#development
nix flake check
```
