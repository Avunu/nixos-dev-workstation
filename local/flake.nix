{
  inputs = {
    nixpkgs.url = "github:numtide/nixpkgs-unfree?ref=nixos-unstable";
    nixos-dev-workstation = {
      url = "github:Avunu/nixos-dev-workstation";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-dev-workstation,
    }:
    let
      hostName = "dev-workstation";
      username = "developer";
      system = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        "${hostName}" = nixpkgs.lib.nixosSystem {
          system = system;
          modules = [
            { nix.nixPath = [ "nixpkgs=${self.inputs.nixpkgs}" ]; }
            nixos-dev-workstation.nixosModules.devWorkstation
            {
              devWorkstation = {
                hostName = hostName;
                diskDevice = "/dev/nvme0n1";
                bootMode = "uefi";
                timeZone = "America/New_York";
                locale = "en_US.UTF-8";
                username = username;
                initialPassword = "password";
                sshKeys = [
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILtMd4jTM9A36iVI2R6zw8cApkd7HQExr0ayfHcwaOp/"
                  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOv4SpIhHJqtRaYBRQOin4PTDUxRwo7ozoQHTUFjMGLW"
                ];
                stateVersion = "25.11";
                extraPackages = with nixpkgs.legacyPackages.${system}; [
                  # Add any additional packages here
                ];
              };
            }
          ];
        };
      };
    };
}
