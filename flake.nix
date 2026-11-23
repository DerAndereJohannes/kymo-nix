# Kymo (github.com/cbrnr/kymo) on Nix.
#
# nix run ~/git/kymo-nix -- file.vhdr    the viewer, with desktop entry, icons and file types
# nix run ~/git/kymo-nix#kymo-main       the viewer from upstream main
# nix develop ~/git/kymo-nix             dev shell for a kymo checkout (real GPU)
# kymo-ci / nix run ~/git/kymo-nix#ci    CI's checks on lavapipe, in a kymo checkout;
#                                        arguments go to `cargo test`
# nix develop ~/git/kymo-nix#test        single tests on lavapipe
#
# overlays.default adds pkgs.kymo (the latest release) and pkgs.kymo-main, built with the
# user's nixpkgs. Their sources are the `kymo` and `kymo-main` inputs; users pick another
# in their own flake, e.g. inputs.kymo-nix.inputs.kymo.url = "github:cbrnr/kymo/<commit>".
#
# From the host: the viewer needs the GPU driver (NixOS: hardware.graphics; elsewhere
# nixGL); the CI checks need nothing.
{
  description = "Kymo, a viewer for large EEG/MEG recordings: package, overlay and dev shells";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    kymo = {
      url = "github:cbrnr/kymo/v0.1.0";
      flake = false;
    };
    kymo-main = {
      url = "github:cbrnr/kymo";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      kymo,
      kymo-main,
      ...
    }:
    let
      lib = nixpkgs.lib;
      forAllSystems =
        f: lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: f nixpkgs.legacyPackages.${system});

      # winit and wgpu dlopen these. An RPATH in kymo's binaries finds them, without
      # LD_LIBRARY_PATH leaking them into every other program.
      libraryPath =
        pkgs:
        lib.makeLibraryPath (
          with pkgs;
          [
            wayland
            libxkbcommon
            vulkan-loader
            libGL
            # X11
            libx11
            libxcursor
            libxi
            libxrandr
            # system fonts in the UI tests
            fontconfig
          ]
        );

      mkKymo =
        pkgs: src:
        pkgs.rustPlatform.buildRustPackage {
          pname = "kymo";
          # Cargo.toml's version and the commit, which says what was built for a release,
          # main and a single commit alike; a local source has no commit.
          version = "${(lib.importTOML "${src}/Cargo.toml").workspace.package.version}+${
            src.shortRev or src.dirtyShortRev or "local"
          }";
          inherit src;
          cargoLock.lockFile = "${src}/Cargo.lock";

          cargoBuildFlags = [
            "-p"
            "kymo"
          ];
          # As the AUR package: the viewer's tests need a GPU and fonts (kymo-ci runs them).
          cargoTestFlags = [
            "-p"
            "kymo-core"
          ];

          # As the release archive (.github/workflows/binaries.yml).
          postInstall = ''
            install -Dm644 packaging/linux/kymo.desktop $out/share/applications/kymo.desktop
            install -Dm644 packaging/linux/kymo.xml $out/share/mime/packages/kymo.xml
            for size in 16 24 32 48 64 128 256 512; do
              install -Dm644 crates/kymo/assets/png/kymo-$size.png \
                $out/share/icons/hicolor/''${size}x''${size}/apps/kymo.png
            done
            install -Dm644 crates/kymo/assets/kymo.svg $out/share/icons/hicolor/scalable/apps/kymo.svg
          '';

          # After fixup, which would shrink it away again.
          postFixup = ''
            patchelf --add-rpath ${libraryPath pkgs} $out/bin/kymo
          '';

          meta = {
            description = "Viewer for large EEG/MEG recordings";
            homepage = "https://github.com/cbrnr/kymo";
            license = lib.licenses.bsd3;
            mainProgram = "kymo";
            platforms = lib.platforms.linux;
          };
        };

      perSystem =
        pkgs:
        let
          toolchain = with pkgs; [
            cargo
            rustc
            clippy
            rustfmt
          ];
          rustflags = "-C link-arg=-Wl,-rpath,${libraryPath pkgs}";
          release = mkKymo pkgs kymo;

          # As CI: lavapipe instead of the GPU, and fixed fonts instead of the system's.
          ciEnv = {
            VK_DRIVER_FILES = "${pkgs.mesa}/share/vulkan/icd.d/lvp_icd.${pkgs.stdenv.hostPlatform.parsed.cpu.name}.json";
            KYMO_REQUIRE_GPU = "1";
            FONTCONFIG_FILE = pkgs.makeFontsConf {
              fontDirectories = with pkgs; [
                noto-fonts
                noto-fonts-color-emoji
              ];
            };
          };

          ci = pkgs.writeShellApplication {
            name = "kymo-ci";
            runtimeInputs = toolchain ++ [ pkgs.stdenv.cc ];
            text = ''
              export RUSTFLAGS="${rustflags}"
              ${lib.concatStrings (lib.mapAttrsToList (k: v: "export ${k}=${v}\n") ciEnv)}
              cargo fmt --all --check
              cargo clippy --workspace --all-targets -- -D warnings
              cargo test --workspace "$@"
            '';
          };

          shell = pkgs.mkShell {
            packages = toolchain ++ [
              pkgs.rust-analyzer
              ci
            ];
            RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
            RUSTFLAGS = rustflags;
          };
        in
        {
          inherit ci;
          packages = {
            kymo = release;
            kymo-main = mkKymo pkgs kymo-main;
            default = release;
          };
          shells = {
            default = shell;
            test = shell.overrideAttrs ciEnv;
          };
        };
    in
    {
      overlays.default = final: prev: {
        kymo = mkKymo final kymo;
        kymo-main = mkKymo final kymo-main;
      };
      packages = forAllSystems (pkgs: (perSystem pkgs).packages);
      devShells = forAllSystems (pkgs: (perSystem pkgs).shells);
      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = lib.getExe (perSystem pkgs).packages.default;
          meta.description = "Kymo, the viewer (latest release)";
        };
        ci = {
          type = "app";
          program = lib.getExe (perSystem pkgs).ci;
          meta.description = "CI's checks (fmt, clippy, tests) on lavapipe";
        };
      });
    };
}
