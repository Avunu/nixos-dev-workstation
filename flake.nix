{
  description = "NixOS Development Workstation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
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
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs supportedSystems f;
    in
    {

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            nativeBuildInputs = [
              (pkgs.writeShellScriptBin "update-flake" ''
                git pull
                nix flake update
                git add flake.lock
                git commit -m "chore: update flake"
                git push
              '')
            ];
            packages = [
              pkgs.mcp-nixos
            ];
          };
        }
      );
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.writeShellApplication {
            name = "install-dev-workstation";
            runtimeInputs = with pkgs; [
              disko
              git
              nix
              nixos-install-tools
              util-linux
              coreutils
            ];
            text = builtins.readFile ./installer.sh;
          };
        }
        // lib.optionalAttrs (system == "x86_64-linux") {
          installerIso = self.nixosConfigurations.installerIso.config.system.build.isoImage;
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
                angrr = {
                  autoUse = true;
                  enable = true;
                };
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
                  libappindicator
                  libappindicator-gtk3
                  libayatana-appindicator
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
                  libsoup_3
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
                  webkitgtk_4_1
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

            # overrides to allow rootless distrobox containers
            system.activationScripts.subuid-persist = {
              text = ''
                echo "${cfg.username}:100000:65536" > /etc/subuid
                echo "${cfg.username}:100000:65536" > /etc/subgid
                chmod 644 /etc/subuid /etc/subgid
              '';
              deps = [ "users" ];
            };

            environment = {
              sessionVariables = {
                PATH = [ "$HOME/.local/bin" ];
              };
              variables.SSH_AUTH_SOCK = "/home/${cfg.username}/.bitwarden-ssh-agent.sock";
              systemPackages =
                with pkgs;
                lib.flatten [
                  (python3.withPackages (
                    ps: with ps; [
                      isort
                      ruff
                      uv
                    ]
                  ))
                  (pkgs.runCommand "custom-distro-icon" { } ''
                    install -D ${./logo.svg} $out/share/icons/hicolor/scalable/apps/distributor-logo.svg
                  '')
                  [
                    android-tools
                    appimage-run
                    beeper
                    bitwarden-desktop
                    boxbuddy
                    bun
                    cloudflared
                    devenv
                    distrobox
                    docker-compose
                    gh
                    gimp
                    git
                    github-desktop
                    gnome-disk-utility
                    gnome-logs
                    google-chrome
                    inkscape
                    libreoffice-fresh
                    msedit
                    nixd
                    nixfmt
                    nodejs
                    obsidian
                    podman-compose
                    podman-desktop
                    pre-commit
                    rclone
                    rustdesk-flutter
                    scrcpy
                    screen
                    service-wrapper
                    thunderbird-latest
                    typescript
                    typescript-language-server
                    usbutils
                    vlc
                    vscode
                    xmind
                  ]
                  cfg.extraPackages
                ];
            };

            users = {
              users = {
                ${cfg.username} = {
                  extraGroups = [
                    "input"
                    "networkmanager"
                    "wheel"
                    "podman"
                  ];
                  openssh.authorizedKeys.keys = cfg.sshKeys;
                };
                root.openssh.authorizedKeys.keys = cfg.sshKeys;
              };
            };

            swapDevices = [
              {
                device = "/var/lib/swapfile";
                size = 16 * 1024;
              }
            ];

            systemd = {
              services.pin-swapfile = {
                description = "Create swap file with filesystem-appropriate attributes";
                wantedBy = [ "var-lib-swapfile.swap" ];
                before = [
                  "create-swap-var-lib-swapfile.service"
                  "var-lib-swapfile.swap"
                ];
                unitConfig = {
                  ConditionPathExists = "!/var/lib/swapfile";
                  # Must disable DefaultDependencies to avoid ordering cycle:
                  # var-lib-swapfile.swap → pin-swapfile → (After=sysinit.target)
                  #   → sysinit.target → swap.target → var-lib-swapfile.swap
                  DefaultDependencies = "no";
                  # Ensure /var/lib is mounted before trying to create the swapfile
                  RequiresMountsFor = "/var/lib";
                };
                serviceConfig.Type = "oneshot";
                script = ''
                  swapfile="/var/lib/swapfile"
                  fstype=$(stat -f -c %T "$swapfile/..")

                  touch "$swapfile"
                  chmod 600 "$swapfile"

                  case "$fstype" in
                    btrfs)
                      chattr +C "$swapfile"
                      btrfs property set "$swapfile" compression ""
                      truncate -s 0 "$swapfile"
                      fallocate -l 16G "$swapfile"
                      ;;
                    f2fs)
                      f2fs_io pinfile set "$swapfile"
                      fallocate -l 16G "$swapfile"
                      ;;
                    *)
                      fallocate -l 16G "$swapfile"
                      ;;
                  esac

                  mkswap "$swapfile"
                '';
                path = with pkgs; [
                  btrfs-progs
                  e2fsprogs
                  f2fs-tools
                  util-linux
                ];
              };
            };

            system.autoUpgrade = {
              allowReboot = mkForce true;
              rebootWindow = mkDefault {
                lower = "01:00";
                upper = "05:00";
              };
            };
          };
        };

      # ================================================================
      # TEMPLATE CONFIG — used only to pre-populate the ISO Nix store.
      # Packages are content-addressed; hostname/username don't affect
      # the package closure, so any valid values work here.
      # ================================================================
      nixosConfigurations.devWorkstationTemplate = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.devWorkstation
          {
            devWorkstation = {
              hostName = "template";
              username = "user";
              diskDevice = "/dev/sda";
            };
          }
        ];
      };

      # ================================================================
      # INSTALLER ISO
      # Boots into an interactive installer that prompts the user for
      # configuration, generates /etc/nixos/flake.nix, then partitions
      # and installs via disko-install.  Assumes the user intends to
      # overwrite any existing local install.
      # Build with: nix build .#installerIso
      # ================================================================
      nixosConfigurations.installerIso = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"

          (
            { pkgs, ... }:
            {
              # Embed this entire flake into the ISO so the installer can
              # reference it as a local path input — same locked nixpkgs,
              # same store paths, no internet required during install.
              environment.etc."installer-flake".source = self;

              # Pre-populate the ISO squashfs with the full package closure
              # of the dev workstation.  disko-install will copy these store
              # paths to the target disk without downloading anything.
              isoImage.storeContents = [
                self.nixosConfigurations.devWorkstationTemplate.config.system.build.toplevel
              ];

              nix.settings.experimental-features = [
                "nix-command"
                "flakes"
              ];

              environment.systemPackages = with pkgs; [
                disko
              ];

              systemd.services.interactive-install = {
                description = "Interactive NixOS Dev Workstation Installer";
                wantedBy = [ "multi-user.target" ];
                after = [
                  "network.target"
                  "polkit.service"
                ];
                conflicts = [ "getty@tty1.service" ];

                serviceConfig = {
                  Type = "oneshot";
                  StandardInput = "tty";
                  StandardOutput = "tty";
                  StandardError = "tty";
                  TTYPath = "/dev/tty1";
                  TTYReset = true;
                  TTYVHangup = true;
                  RemainAfterExit = true;
                };

                path = with pkgs; [
                  bash
                  coreutils
                  disko
                  git
                  nix
                  nixos-install-tools
                  util-linux
                ];

                script = builtins.readFile ./installer.sh;
              };
            }
          )
        ];
      };
    };
}
