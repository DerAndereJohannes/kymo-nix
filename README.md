# kymo-nix

A Nix flake for [Kymo](https://github.com/cbrnr/kymo), a viewer for large EEG/MEG recordings: the package (with desktop entry, icons and file types), an overlay and a dev shell for working on Kymo.

## Run

```
nix run github:DerAndereJohannes/kymo-nix -- recording.vhdr
```

## Install on NixOS

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    kymo-nix = {
      url = "github:DerAndereJohannes/kymo-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # ...
  };

  outputs =
    { nixpkgs, home-manager, kymo-nix, ... }:
    {
      nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          home-manager.nixosModules.home-manager
          (
            { pkgs, ... }:
            {
              nixpkgs.overlays = [ kymo-nix.overlays.default ];

              home-manager.useGlobalPkgs = true;
              home-manager.users.alice = {
                home.packages = [ pkgs.kymo ]; # or pkgs.kymo-main
                # ...
              };
            }
          )
          # ...
        ];
      };
    };
}
```

Without home-manager: `environment.systemPackages = [ pkgs.kymo ];`. The overlay builds with your nixpkgs, which needs to be nixos-26.05 or newer (Kymo needs Rust 1.95).

## Choose a version

`kymo` is the latest release, `kymo-main` upstream main. Either can point elsewhere in your flake, e.g. `kymo`:

```nix
inputs.kymo-nix.inputs.kymo.url = "github:cbrnr/kymo/v0.1.0";     # a release
inputs.kymo-nix.inputs.kymo.url = "github:cbrnr/kymo/<commit>";   # a commit (full hash)
```

## Develop

In a Kymo checkout:

```
nix develop github:DerAndereJohannes/kymo-nix        # toolchain and runtime libraries
kymo-ci                                              # CI's checks: fmt, clippy, tests on lavapipe
```

The viewer needs a GPU driver from the host (NixOS: `hardware.graphics`; elsewhere nixGL).
