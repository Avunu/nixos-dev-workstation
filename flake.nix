{
  description = "NixOS Development Workstation";

  inputs = {
    nixpkgs.url = "github:numtide/nixpkgs-unfree?ref=nixos-unstable";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-micro-desktop = {
      url = "github:Avunu/nixos-micro-desktop/niri";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-rclone = {
      url = "github:Avunu/nixos-rclone";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      ...
    }:
    let
      lib = nixpkgs.lib;
    in
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs supportedSystems f;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.writeShellApplication {
            name = "install-dev-workstation";
            runtimeInputs = with pkgs; [
              git
              nix
              util-linux
              coreutils
            ];
            text = builtins.readFile ./installer.sh;
          };
        }
      );

      nixosModules.devWorkstation =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        with lib;
        let
          cfg = config.devWorkstation;
        in
        {
          imports = [
            inputs.nixos-micro-desktop.nixosModules.microDesktop
            inputs.nixos-rclone.nixosModules.default
            inputs.agenix.nixosModules.default
          ];

          options.devWorkstation = {
            hostName = mkOption {
              type = types.str;
              description = "Hostname for the system";
            };
            diskDevice = mkOption {
              type = types.str;
              default = "/dev/sda";
              description = "Disk device for installation";
            };
            bootMode = mkOption {
              type = types.enum [
                "uefi"
                "legacy"
              ];
              default = "uefi";
              description = "Boot mode: uefi (systemd-boot) or legacy (GRUB)";
            };
            timeZone = mkOption {
              type = types.str;
              default = "America/New_York";
              description = "System timezone";
            };
            locale = mkOption {
              type = types.str;
              default = "en_US.UTF-8";
              description = "System locale";
            };
            username = mkOption {
              type = types.str;
              description = "Primary user name";
            };
            initialPassword = mkOption {
              type = types.str;
              default = "password";
              description = "Initial password for the user";
            };
            sshKeys = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "SSH public keys for user and root";
            };
            stateVersion = mkOption {
              type = types.str;
              default = "25.11";
              description = "NixOS state version";
            };
            extraPackages = mkOption {
              type = types.listOf types.package;
              default = [ ];
              description = "Additional packages to install";
            };
            enableVpn = mkOption {
              type = types.bool;
              default = false;
              description = "Enable VPN support";
            };
          };

          config = {
            microDesktop = {
              hostName = cfg.hostName;
              diskDevice = cfg.diskDevice;
              bootMode = cfg.bootMode;
              timeZone = cfg.timeZone;
              locale = cfg.locale;
              username = cfg.username;
              initialPassword = cfg.initialPassword;
              stateVersion = cfg.stateVersion;
              enableVpn = cfg.enableVpn;
              enableSsh = true;
              sshPasswordAuth = false;
              sshRootLogin = "prohibit-password";
            };

            age = {
              identityPaths = [ "/etc/agenix/key" ];
              secrets.rclone = {
                file = ./secrets/rclone.age;
                mode = "0400";
                owner = "root";
                group = "root";
              };
            };

            services.rclone-remotes = {
              enable = true;
              defaultConfigFile = config.age.secrets.rclone.path;
              defaultUser = cfg.username;
              defaultGroup = "users";
              bisyncs.clients = {
                remote = "vivobox:client";
                localPath = "/home/${cfg.username}/Clients";
                user = cfg.username;
                group = "users";
              };
            };

            programs = {
              direnv = {
                enable = true;
                nix-direnv.enable = true;
                enableBashIntegration = true;
              };
              git = {
                enable = true;
                config.safe.directory = [ "/etc/nixos" ];
              };
            };

            virtualisation = {
              containers.enable = true;
              oci-containers.backend = "podman";
              podman = {
                autoPrune.enable = true;
                defaultNetwork.settings.dns_enabled = true;
                dockerCompat = true;
                dockerSocket.enable = true;
                enable = true;
              };
            };

            environment = {
              variables.SSH_AUTH_SOCK = "/home/${cfg.username}/.bitwarden-ssh-agent.sock";
              systemPackages =
                with pkgs;
                lib.flatten [
                  (python3.withPackages (ps: with ps; [ uv ]))
                  [
                    appimage-run
                    beeper
                    bitwarden-desktop
                    bun
                    docker-compose
                    gh
                    gimp
                    git
                    github-desktop
                    gnome-disk-utility
                    google-chrome
                    inkscape
                    libreoffice-fresh
                    nixfmt
                    obsidian
                    podman-compose
                    podman-desktop
                    rustdesk-flutter
                    service-wrapper
                    vlc
                    vscode
                  ]
                  cfg.extraPackages
                ];
            };

            users.users.${cfg.username} = {
              extraGroups = [
                "input"
                "networkmanager"
                "wheel"
                "podman"
              ];
              openssh.authorizedKeys.keys = cfg.sshKeys;
            };
            users.users.root.openssh.authorizedKeys.keys = cfg.sshKeys;

            systemd = {
              services.flake-update = {
                unitConfig = {
                  Description = "Update flake inputs";
                  StartLimitIntervalSec = 300;
                  StartLimitBurst = 5;
                };
                serviceConfig = {
                  ExecStart = "${pkgs.nix}/bin/nix flake update --flake /etc/nixos";
                  Restart = "on-failure";
                  RestartSec = "120s";
                  Type = "oneshot";
                  User = "root";
                  Environment = "HOME=/root";
                };
                wants = [ "network-online.target" ];
                after = [ "network-online.target" ];
                before = [ "nixos-upgrade.service" ];
                path = with pkgs; [
                  nix
                  git
                  host
                ];
                requiredBy = [ "nixos-upgrade.service" ];
              };
              timers.flake-update = {
                wantedBy = [ "timers.target" ];
                timerConfig = {
                  OnCalendar = "hourly";
                  Persistent = true;
                  Unit = "flake-update.service";
                };
              };
            };

            system.autoUpgrade = {
              allowReboot = mkDefault true;
              enable = mkDefault true;
              flags = [
                "--update-input"
                "nixpkgs"
                "--impure"
              ];
              flake = mkDefault "/etc/nixos";
              rebootWindow = mkDefault {
                lower = "01:00";
                upper = "05:00";
              };
            };
          };
        };
    };
}
