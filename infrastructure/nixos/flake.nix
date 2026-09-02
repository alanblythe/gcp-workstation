{
  description = "gcp-workstation NixOS configuration for GCE";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators }:
    let
      system = "x86_64-linux";
    in
    {
      # Used by `nixos-rebuild` once the VM is running NixOS.
      nixosConfigurations.workstation = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./configuration.nix ];
      };

      # Used by `make image` (see Makefile) to produce a GCE-format raw
      # tarball that we upload and register as a custom image.
      packages.${system}.gce-image = nixos-generators.nixosGenerate {
        inherit system;
        format = "gce";
        modules = [ ./configuration.nix ];
      };
    };
}
