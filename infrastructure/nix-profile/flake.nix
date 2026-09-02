# User-level workstation tooling, declared as a Nix flake.
#
# Why: scripts/post-create.sh used to install gcloud / opentofu / pack /
# jupyter / etc. via a mix of apt repos, curl|tar pipes, and npm-global. That
# works but isn't reproducible — tool versions drifted, no lockfile, hard to
# roll back. This flake replaces that for everything that's "just a binary on
# PATH". System-level integrations (Docker, Chrome Remote Desktop, X / xfce,
# Chrome Remote Desktop's PAM hooks) stay in apt / startup.sh because they
# need init/systemd/PAM glue that's awkward to express user-side.
#
# Install:    nix profile install /mnt/data/repos/gcp-workstation/infrastructure/nix-profile
# Update:     nix profile upgrade --all   (after `git pull`)
# List:       nix profile list
# Remove:     nix profile remove workstation-tools
#
# `flake.lock` pins nixpkgs — commit it so future installs are reproducible.

{
  description = "gcp-workstation user-level tooling";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;  # gemini-cli, google-cloud-sdk
      };
    in
    {
      packages.${system}.default = pkgs.buildEnv {
        name = "workstation-tools";

        # Mirrors infrastructure/nixos/configuration.nix's environment.systemPackages,
        # minus the things that have to live system-side (chrome-remote-desktop,
        # google-chrome) and minus the xfce session bits. If you change one
        # list, change the other so a future NixOS attempt has parity.
        paths = with pkgs; [
          # Cloud
          google-cloud-sdk
          opentofu

          # Build / container
          pack            # Cloud-Native Buildpacks 'pack' CLI

          # Languages
          nodejs_22
          # Use a single python env so the `jupyter` launcher script and its
          # subcommands all see the same site-packages. Adding jupyter as a
          # bare `python3Packages.jupyter` next to `python3` only exposes
          # `jupyter-notebook` to bin/, not `jupyter` itself.
          (python3.withPackages (ps: with ps; [
            pip
            ipykernel
            jupyter
            notebook
          ]))

          # AI tooling — replaces the npm-install of @google/gemini-cli
          gemini-cli

          # General CLI
          git
          curl
          wget
          jq
          rsync
          unzip
          tree
          htop
          tmux
          file
          ripgrep
        ];
      };
    };
}
