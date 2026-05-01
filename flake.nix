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
              default = "/dev/nvme0n1";
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

            boot = {
              kernelPackages = pkgs.linuxPackages_zen;
              plymouth.logo = ./logo.png;
            };

            programs = {
              appimage.enable = true;
              direnv = {
                enable = true;
                nix-direnv.enable = true;
                enableBashIntegration = true;
              };
              fuse = {
                enable = true;
              };
              git = {
                enable = true;
                config.safe.directory = [ "/etc/nixos" ];
              };
              nix-ld = {
                enable = true;
                libraries = with pkgs; [
                  alsa-lib
                  at-spi2-atk
                  at-spi2-core
                  bison
                  bzip2
                  cairo
                  cups
                  curl
                  dbus
                  dbus-glib
                  dri-pkgconfig-stub
                  expat
                  ffmpeg
                  flac
                  fontconfig
                  freetype
                  fuse2
                  fuse3
                  gdk-pixbuf
                  glib
                  glibc
                  gperf
                  gtk3.out
                  gtk4.out
                  harfbuzz
                  kdePackages.kcachegrind
                  kdePackages.polkit-kde-agent-1
                  kdePackages.polkit-qt-1
                  khronos-ocl-icd-loader
                  libaio
                  libcap
                  libdmx
                  libdrm
                  libepoxy
                  libevdev
                  libevent
                  libffi
                  libfontenc
                  libFS
                  libgbm
                  libGL
                  libGLU
                  libICE
                  libjpeg
                  libkrb5
                  libnotify
                  libopus
                  libpciaccess
                  libpng
                  libpthreadstubs
                  libpulseaudio
                  libsecret
                  libSM
                  libunwind
                  libusb1
                  libva
                  libwebp
                  libX11
                  libXau
                  libXaw
                  libxcb
                  libXcomposite
                  libxcrypt
                  libxcrypt-legacy
                  libXcursor
                  libxcvt
                  libXdamage
                  libXdmcp
                  libXext
                  libXfixes
                  libXfont
                  libXfont2
                  libXft
                  libXi
                  libXinerama
                  libxkbcommon
                  libxkbfile
                  libxml2
                  libXmu
                  libXp
                  libXpm
                  libXpresent
                  libXrandr
                  libXrender
                  libXres
                  libXScrnSaver
                  libxshmfence
                  libxslt
                  libXt
                  libXtst
                  libXv
                  libXvMC
                  minizip
                  nasm
                  ncurses5
                  nspr
                  nss
                  numactl
                  openssl
                  pango
                  pciutils
                  pcre2
                  pipewire
                  polkit
                  polkit_gnome
                  protobuf
                  re2
                  snappy
                  speechd-minimal
                  speex
                  systemd
                  unzip
                  util-linux
                  vulkan-loader
                  vulkan-tools
                  wayland
                  zlib-ng
                ];
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
                  (pkgs.runCommand "custom-distro-icon" { } ''
                    install -D ${./logo.svg} $out/share/icons/hicolor/scalable/apps/distributor-logo.svg
                  '')
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

            swapDevices = [
              {
                device = "/var/lib/swapfile";
                size = 16 * 1024;
              }
            ];

            systemd = {
              services.f2fs-pin-swapfile = {
                description = "Create F2FS swap file with compression disabled";
                wantedBy = [ "var-lib-swapfile.swap" ];
                before = [
                  "create-swap-var-lib-swapfile.service"
                  "var-lib-swapfile.swap"
                ];
                unitConfig.ConditionPathExists = "!/var/lib/swapfile";
                serviceConfig.Type = "oneshot";
                script = ''
                  fallocate -l ${toString (16 * 1024)}M /var/lib/swapfile
                  f2fs_io pin set 1 /var/lib/swapfile
                  chmod 600 /var/lib/swapfile
                  mkswap /var/lib/swapfile
                '';
                path = with pkgs; [
                  f2fs-tools
                  util-linux
                ];
              };
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
              allowReboot = mkForce true;
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
