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
    nixos-install-helper = {
      url = "github:Avunu/nixos-install-helper";
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

      # Installer surface (nixos-install-helper). devWorkstation layers on
      # microDesktop, so optionRoots names BOTH namespaces — the declaration-source
      # default would miss microDesktop's options (declared in the upstream flake).
      ih = inputs.nixos-install-helper.lib.mkProject {
        inherit nixpkgs self;
        system = "x86_64-linux";
        installModules = [ self.nixosModules.devWorkstation ];
        optionRoots = [
          "devWorkstation"
          "microDesktop"
        ];
        flakeStyle = "local";
        upstream = "github:Avunu/nixos-dev-workstation";
        hints.diskDevice = "disk-device";
        assets = [
          {
            name = "agenix-key";
            target = "/etc/agenix/key";
            mode = "0400";
            required = true;
            source = {
              env = "agenix__key";
              prompt = "paste";
            };
          }
        ];
      };
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
      # Installer artifacts (x86_64): settingsSchema + unattended/guided ISOs,
      # default = the unattended ISO. The old install-dev-workstation wrapper is
      # superseded by `nix run` (the wizard).
      packages.x86_64-linux = ih.packages.x86_64-linux // {
        default = ih.packages.x86_64-linux.installerIso;
      };

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
          editRcloneConfig = pkgs.writeShellApplication {
            name = "edit-rclone-config";
            runtimeInputs = with pkgs; [
              inputs.agenix.packages.${system}.default
              rclone
            ];
            text = ''
              set -euo pipefail
              TMPCONF="$(mktemp --suffix=.conf)"
              trap 'rm -f "$TMPCONF"' EXIT
              cd /etc/nixos

              SECRET="secrets/rclone.age"
              IDENTITY_FLAG=""

              while getopts "i:" opt; do
                case "$opt" in
                  i) IDENTITY_FLAG="-i $OPTARG" ;;
                  *) echo "Usage: edit-rclone-config [-i key-file]" >&2; exit 1 ;;
                esac
              done

              if [ -f "$SECRET" ]; then
                echo "Decrypting rclone config..."
                # shellcheck disable=SC2086
                agenix $IDENTITY_FLAG -d "$SECRET" > "$TMPCONF"
              else
                echo "No existing secret found, starting with empty config."
                touch "$TMPCONF"
              fi

              chmod 600 "$TMPCONF"
              echo "Launching rclone config..."
              ${pkgs.rclone}/bin/rclone --config "$TMPCONF" config

              echo "Re-encrypting to $SECRET..."
              # shellcheck disable=SC2086
              agenix $IDENTITY_FLAG -e "$SECRET" < "$TMPCONF"
              echo "Done. Secret updated."
            '';
          };
          # Build our global npm utilities cleanly from the lockfile
          globalNpmTools = pkgs.buildNpmPackage {
            pname = "global-npm-tools";
            version = "1.0.0";

            # Point to the directory containing your package.json & package-lock.json
            src = ./global-npm-tools;

            npmDeps = pkgs.importNpmLock {
              npmRoot = ./global-npm-tools;
            };

            npmConfigHook = pkgs.importNpmLock.npmConfigHook;

            # This prevents Nix from attempting to run a production bundler
            # since we only care about the CLI binaries inside node_modules
            dontNpmBuild = true;
          };
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
              default = "nixos";
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
              default = "user";
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
              # kernelPackages = pkgs.linuxPackages_zen;
              plymouth.logo = ./logo.png;
            };

            environment = {
              sessionVariables = {
                PATH = [ "$HOME/.local/bin" ];
              };
              variables.SSH_AUTH_SOCK = "/home/${cfg.username}/.bitwarden-ssh-agent.sock";
              systemPackages =
                with pkgs;
                lib.flatten [
                  editRcloneConfig
                  # globalNpmTools
                  (python3.withPackages (
                    ps: with ps; [
                      cffi
                      installer
                      isort
                      pkgconfig
                      poetry-core
                      pycparser
                      ruff
                      setuptools
                      ty
                      uv
                      wheel
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
                    cacert
                    cloudflared
                    coreutils
                    distrobox
                    docker-compose
                    file
                    findutils
                    gh
                    gimp
                    git
                    github-desktop
                    gnome-disk-utility
                    gnome-logs
                    gnugrep
                    gnumake
                    gnused
                    google-chrome
                    inkscape
                    jq
                    libreoffice-fresh
                    msedit
                    nixd
                    nixfmt
                    nodejs_26
                    obsidian
                    pkg-config
                    podman-compose
                    podman-desktop
                    powershell
                    pre-commit
                    rclone
                    #rustdesk
                    scrcpy
                    screen
                    service-wrapper
                    solaar
                    stdenv.cc
                    thunderbird-latest
                    typescript
                    typescript-language-server
                    usbutils
                    vips
                    vlc
                    vscode
                    which
                    xmind
                  ]
                  cfg.extraPackages
                ];
            };

            hardware.logitech.wireless.enable = true;

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
                  vips
                  # vulkan-loader
                  # vulkan-tools
                  wayland
                  webkitgtk_4_1
                  zlib-ng
                ];
              };
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

            # 16 GiB disk swap as a last-resort safety net behind zram.
            # Note: microDesktop sets vm.page-cluster=0 (single-page reads, optimal
            # for zram).  If the kernel falls through to this disk swap, performance
            # will be poor.  The disk swap is not expected to be used under normal
            # load; if you see regular disk swap activity, consider increasing RAM
            # or overriding vm.page-cluster to 3 (32 pages / 128 KiB reads).
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

            # overrides to allow rootless distrobox containers
            system.activationScripts.subuid-persist = {
              text = ''
                echo "${cfg.username}:100000:65536" > /etc/subuid
                echo "${cfg.username}:100000:65536" > /etc/subgid
                chmod 644 /etc/subuid /etc/subgid
              '';
              deps = [ "users" ];
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

          };
        };

      # ================================================================
      # TEMPLATE CONFIG — used only to pre-populate the ISO Nix store.
      # Packages are content-addressed; hostname/username don't affect
      # the package closure, so any valid values work here.
      # ================================================================
      # install / installTemplate systems (the latter pre-populates the offline
      # ISO closure, replacing the old devWorkstationTemplate).
      nixosConfigurations = ih.nixosConfigurations;

      # configure / install / deploy / wizard (`nix run`) apps.
      apps = ih.apps;
    };
}
