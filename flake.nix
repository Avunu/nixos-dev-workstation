{
  description = "NixOS Development Workstation";

  # Determinate Nix is built from nix-src, which cache.nixos.org does not
  # carry. Without this, the first `nix run` / `nix build` of this flake from a
  # machine that is not yet on Determinate compiles Nix itself. Once a machine
  # runs Determinate Nix, determinate-nixd configures its own caches and this
  # is no longer needed there. Same key as the --option flags in the readme.
  nixConfig = {
    extra-substituters = [ "https://install.determinate.systems" ];
    extra-trusted-public-keys = [
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-micro-desktop = {
      url = "github:Avunu/nixos-micro-desktop";
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

      # Installer surface (nixos-install-helper). devWorkstation re-declares every
      # technician-facing option and passes it through to microDesktop (and fixes
      # enableSsh / ssh policy), so ONLY devWorkstation is a root — listing
      # microDesktop too would prompt each shared option twice and write downstream
      # values the passthrough immediately overrides.
      ih = inputs.nixos-install-helper.lib.mkProject {
        inherit nixpkgs self;
        system = "x86_64-linux";
        installModules = [ self.nixosModules.devWorkstation ];
        optionRoots = [
          "devWorkstation"
        ];
        flakeStyle = "local";
        upstream = "github:Avunu/nixos-dev-workstation";
        # `nix run github:Avunu/nixos-dev-workstation#new-host` creates a private
        # Avunu/host-<name> repo for one machine, which the machine then tracks
        # (see the readme's "Managed from a host repo").
        hostRepo = {
          owner = "Avunu";
          adminKeys = [
            # kevin
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOv4SpIhHJqtRaYBRQOin4PTDUxRwo7ozoQHTUFjMGLW"
            # gideon
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHZ2QESOCg6FpzUrq/7dmsFZV9WjUWOE/YA8ywNj4xJb"
          ];
        };
        hints.diskDevice = "disk-device";
        assets = [
          {
            # Optional: nothing in this module declares age.secrets, so the
            # agenix module stays disabled and a machine installs and boots
            # fine without the key. It is only needed once a consumer adds
            # secrets of its own. Unset, the unattended ISO is built without
            # it and the guided/network installers just offer to provide it.
            # (A host repo uses the machine's SSH host key instead; this key
            # is the alternative for a machine without one.)
            name = "agenix-key";
            target = "/etc/agenix/key";
            mode = "0400";
            required = false;
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

          # Installed from, and tracking, its own host repository.
          repoManaged = config.installHelper.enable && config.installHelper.flakeStyle == "repo";

          # Chromium-family hardware acceleration flags.
          #
          # Every Chromium and Electron app on this workstation ships with
          # VA-API off. The hardware is there — on Kaby Lake, `vainfo` reports
          # the iHD driver with H.264, HEVC, VP8, VP9 and JPEG decode plus
          # H.264/HEVC encode, and a VA-API transcode of the same clip costs
          # 69% of one CPU against 293% for the software path — but nothing
          # reaches for it. Reading drm-engine-video out of /proc/*/fdinfo
          # across every browser and Electron process on a machine that had
          # been up 22 hours returned exactly zero nanoseconds: not one frame
          # had ever been decoded on the video engine. Every video these apps
          # play is decoded on a CPU that is already the bottleneck.
          #
          # The Vaapi* features are listed together because Chromium's own
          # gate has moved between them across releases and it ignores names
          # it does not recognise, so naming several is safe and naming one is
          # a bet on a version. WaylandWindowDecorations is repeated from the
          # nixpkgs wrappers' own NIXOS_OZONE_WL block: a second
          # --enable-features overrides the first rather than merging with it,
          # so anything that block would have set has to be restated here.
          #
          # --ignore-gpu-blocklist is aimed at Claude Desktop specifically
          # (see claudeDesktop below) and is inert where the GPU is already in
          # use, which for Chrome and VSCode it demonstrably is — 55 s and
          # 302 s of render-engine time respectively over that same 22 hours.
          chromiumGpuFlags = concatStringsSep " " [
            "--ignore-gpu-blocklist"
            "--enable-zero-copy"
            "--enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoDecoder,VaapiVideoEncoder,VaapiIgnoreDriverChecks,WaylandWindowDecorations"
          ];

          # Claude Desktop, with the flags above.
          #
          # Unlike its Electron siblings it does no GPU work at all: zero
          # nanoseconds on every engine across all of its processes over 22
          # hours, while VSCode — same Chromium, same session — accumulated
          # 302 s on the render engine. Its live GPU process carried
          # --use-gl=disabled, which a freshly-created profile does not, so
          # the app is falling back to software compositing at some point
          # during a session rather than being configured that way.
          #
          # --ignore-gpu-blocklist is the standard remedy for that fallback
          # and it does change what the GPU process is launched with. It has
          # NOT been shown to restore GPU compositing here, because the
          # fallback takes hours to reproduce and a short run renders nothing
          # measurable either way. Treat this one as a mitigation to verify in
          # normal use, not as a fix already demonstrated:
          #
          #   grep -H drm-engine /proc/$(pgrep -f 'claude-desktop.*gpu-process')/fdinfo/* \
          #     | grep -v ':\s*0 ns'
          #
          # A wrapper rather than an override because the package comes from
          # the llm-agents flake and takes no commandLineArgs argument. The
          # .desktop files launch it as bare `claude-desktop` off PATH, so
          # they pick this up without needing to be rewritten.
          claudeDesktop =
            let
              base = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-desktop;
            in
            pkgs.symlinkJoin {
              name = "claude-desktop-accelerated";
              paths = [ base ];
              nativeBuildInputs = [ pkgs.makeWrapper ];
              postBuild = ''
                wrapProgram $out/bin/claude-desktop \
                  --add-flags ${escapeShellArg chromiumGpuFlags}
              '';
              inherit (base) meta;
            };

          customDistroIcon = (
            pkgs.runCommand "custom-distro-icon" { } ''
              install -D ${./logo.svg} $out/share/icons/hicolor/scalable/apps/distributor-logo.svg
            ''
          );

          # config.nix.package rather than pkgs.nix in both scripts below: it is
          # the Nix the daemon is running (Determinate Nix), not nixpkgs'.
          devShellInit = pkgs.writeShellApplication {
            name = "devsh";
            runtimeInputs = [
              config.nix.package
            ];
            text = ''
              nix develop --no-pure-eval
            '';
          };

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
              # A checkout of the machine's host repo when run from one;
              # otherwise the local install's /etc/nixos.
              if [ ! -f secrets.nix ]; then
                cd /etc/nixos
              fi

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

            # Only the manifests; keeps a local `npm install` in
            # ./global-npm-tools from leaking node_modules into the build, which
            # would make npm consider the tree "up to date" and skip unpacking.
            src = lib.fileset.toSource {
              root = ./global-npm-tools;
              fileset = lib.fileset.unions [
                ./global-npm-tools/package.json
                ./global-npm-tools/package-lock.json
              ];
            };

            npmDeps = pkgs.importNpmLock {
              npmRoot = ./global-npm-tools;
            };

            npmConfigHook = pkgs.importNpmLock.npmConfigHook;

            # This prevents Nix from attempting to run a production bundler
            # since we only care about the CLI binaries inside node_modules
            dontNpmBuild = true;

            # The `bun` npm package ships a placeholder bin/bun.exe and a
            # postinstall (`node install.js`) that resolves
            # @oven/bun-<platform>/bin/bun and then *executes* it with
            # `--version` to validate it before moving it into place. That
            # prebuilt ELF wants /lib64/ld-linux-x86-64.so.2, which exists
            # neither in the build sandbox nor on NixOS, so the exec fails and
            # install.js reports the misleading
            # `Failed to find package "@oven/bun-linux-x64"` before trying to
            # re-download it over the (sandboxed, offline) network.
            # Skip install scripts and do the postinstall's job below instead.
            npmRebuildFlags = [ "--ignore-scripts" ];

            nativeBuildInputs = [ pkgs.autoPatchelfHook ];
            buildInputs = [ pkgs.openssl ];

            # Promote the platform binary that install.js would have installed,
            # and repoint the `bun` package's placeholders at it so anything
            # resolving through node_modules/.bin also works.
            postInstall = ''
              pkgdir="$out/lib/node_modules/global-npm-tools"
              install -Dm755 "$pkgdir/node_modules/@oven/bun-linux-x64/bin/bun" "$out/bin/bun"
              ln -s bun "$out/bin/bunx"
              # Symlink rather than ship a second 80 MB copy of the binary.
              ln -sf "$out/bin/bun" "$pkgdir/node_modules/@oven/bun-linux-x64/bin/bun"
              ln -sf "$out/bin/bun" "$pkgdir/node_modules/bun/bin/bun.exe"
              ln -sf "$out/bin/bun" "$pkgdir/node_modules/bun/bin/bunx.exe"
            '';
          };

          systemOptimize = pkgs.writeShellApplication {
            name = "system-optimize";
            runtimeInputs = [
              config.nix.package
            ];
            text = ''
              nix-env --delete-generations old
              sudo nix-env -p /nix/var/nix/profiles/system --delete-generations old
              sudo nix-collect-garbage -d
              rm -rf ~/.cache/nix
              rm -rf ~/.cache/nix-eval-cache
              sudo nix-store --optimize
            '';
          };
        in
        {
          imports = [
            # Swaps nix.package for Determinate Nix and runs the daemon as
            # determinate-nixd, which owns /etc/nix/nix.conf; everything NixOS
            # generates from nix.settings (here and in microDesktop) moves to
            # nix.custom.conf, which it includes. determinate-nixd appends its
            # own extra-substituters and extra-experimental-features after
            # that include, so those settings add to Determinate's rather than
            # replace them. `determinate.enable = false` backs it out.
            inputs.determinate.nixosModules.default
            inputs.nixos-micro-desktop.nixosModules.microDesktop
            inputs.nixos-rclone.nixosModules.default
            inputs.agenix.nixosModules.default
            # For installHelper.flakeStyle/repo, read below. mkProject imports
            # the same file into its install systems; the module system
            # de-duplicates it by path.
            inputs.nixos-install-helper.nixosModules.installHelper
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
            rootFilesystem = mkOption {
              type = types.enum [
                "btrfs"
                "f2fs"
              ];
              default = "f2fs";
              description = "Root filesystem type";
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
            swapSizeGiB = mkOption {
              type = types.ints.unsigned;
              default = 32;
              description = "Swap size in GiB";
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
            # Every agenix identity this machine might have, so secrets decrypt
            # whichever one it was given: the SSH host key (a host repo mints it)
            # or the optional installer asset. agenix skips paths that don't exist.
            age.identityPaths = mkForce (
              [ "/etc/agenix/key" ]
              ++ map (k: k.path) (
                filter (k: k.type == "ed25519" || k.type == "rsa") config.services.openssh.hostKeys
              )
            );

            # Inert unless something turns it on: mkProject does (its install
            # systems), the /etc/nixos flake of a local install does not.
            installHelper = {
              enable = mkDefault false;
              # micro-desktop's system-upgrade timer is the upgrade mechanism
              # (it waits for an idle, unmetered machine); point it at the repo
              # rather than running system.autoUpgrade beside it.
              repo.autoUpgrade = mkIf repoManaged false;
            };

            # Determinate's module points the nixpkgs registry entry at its own
            # weekly nixpkgs tarball. It does so at priority 750, which beats
            # the mkDefault pin NixOS puts on the nixpkgs this system was built
            # from (nixpkgs.flake.setFlakeRegistry), so without this `nixpkgs#foo`
            # and <nixpkgs> would quietly stop meaning "the revision I am
            # running". Same pin as before, at a priority between the two.
            # Deleting it takes Determinate's weekly nixpkgs instead, and lets
            # go of the ~210 MB source tree this pin keeps in the closure.
            nix.registry.nixpkgs.to = mkIf config.nixpkgs.flake.setFlakeRegistry (
              mkOverride 500 {
                type = "path";
                path = config.nixpkgs.flake.source;
              }
            );

            # llm-agents
            nix.settings = {
              extra-substituters = [ "https://cache.numtide.com" ];
              extra-trusted-public-keys = [
                "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
              ];
            };
            # nixpkgs' vscode (nixos-unstable, 1.129.x) ships the vsce-sign
            # extension-signature verifier without its execute bit. VSCode
            # execFile()s node_modules/@vscode/vsce-sign/bin/vsce-sign to check
            # signatures, hits EACCES, and every extension install fails unless the
            # user manually clicks "Install anyway" (donotVerifySignature). The
            # binary is a correctly patchelf'd native executable (clean ldd, runs
            # fine once +x is restored) - so fixing the permission bit REPAIRS
            # signature verification rather than disabling it.
            nixpkgs.overlays = [
              (final: prev: {
                # Both browsers take their launch flags through the
                # commandLineArgs override argument, which the nixpkgs wrappers
                # append to the exec line. See chromiumGpuFlags above for what
                # is being passed and why.
                google-chrome = prev.google-chrome.override {
                  commandLineArgs = chromiumGpuFlags;
                };
                vscode =
                  (prev.vscode.override {
                    commandLineArgs = chromiumGpuFlags;
                  }).overrideAttrs
                    (old: {
                      postFixup = (old.postFixup or "") + ''
                        find "$out/lib/vscode/resources/app" \
                          -path '*/@vscode/vsce-sign/bin/vsce-sign' \
                          -exec chmod +x {} +
                      '';
                    });
              })
            ];

            microDesktop = {
              bootMode = cfg.bootMode;
              diskDevice = cfg.diskDevice;
              enableSsh = true;
              enableVpn = cfg.enableVpn;
              hostName = cfg.hostName;
              initialPassword = cfg.initialPassword;
              locale = cfg.locale;
              rootFilesystem = cfg.rootFilesystem;
              sshPasswordAuth = false;
              sshRootLogin = "prohibit-password";
              stateVersion = cfg.stateVersion;
              # Larger than microDesktop's 8 GiB default: this machine used to
              # carry its own separate 16 GiB /var/lib/swapfile on top of the
              # upstream partition (two redundant swap tiers). It now relies
              # solely on microDesktop's disko-managed partition, sized to
              # match what the swapfile used to provide.
              swapSizeGiB = cfg.swapSizeGiB;
              timeZone = cfg.timeZone;
              upgradeFlake = mkIf repoManaged config.installHelper.repo.flakeRef;
              username = cfg.username;
            };

            boot = {
              # kernelPackages = pkgs.linuxPackages_zen;
              plymouth.logo = ./logo.png;
            };

            environment = {
              sessionVariables = {
                PATH = [ "$HOME/.local/bin" ];
              };
              variables = {
                EDITOR = "${pkgs.msedit}/bin/edit";
                SSH_AUTH_SOCK = "/home/${cfg.username}/.bitwarden-ssh-agent.sock";
              };
              systemPackages =
                with pkgs;
                lib.flatten [
                  inputs.agenix.packages.${system}.default
                  inputs.llm-agents.packages.${system}.claude-code
                  claudeDesktop
                  customDistroIcon
                  devShellInit
                  editRcloneConfig
                  systemOptimize
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
                  [
                    appimage-run
                    baobab
                    beeper
                    bitwarden-desktop
                    bun
                    cacert
                    cloudflared
                    coreutils
                    dmidecode
                    dnslookup
                    docker-compose
                    file
                    findutils
                    firefox
                    gh
                    gimp
                    git
                    github-desktop
                    gnome-disk-utility
                    gnome-logs
                    gnome-text-editor
                    gnugrep
                    gnumake
                    gnused
                    google-chrome
                    inkscape
                    jq
                    killall
                    libreoffice-stable
                    msedit
                    nirimod
                    nixd
                    nixfmt
                    nodejs_26
                    nushell
                    obsidian
                    opencode
                    opencode-desktop
                    openlogi
                    p7zip
                    pciutils
                    pkg-config
                    podman-compose
                    podman-desktop
                    powershell
                    pre-commit
                    rclone
                    remmina
                    ripgrep
                    rustdesk-flutter
                    scrcpy
                    screen
                    service-wrapper
                    stdenv.cc
                    thunderbird-latest
                    typescript
                    unzip
                    usbutils
                    usbutils
                    vips
                    vlc
                    vscode
                    which
                    wl-mirror
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
                # nix-direnv 3.2.0 bug (nix-community/nix-direnv#786): the
                # cached-shell path calls _nix_refresh_gcroots, whose
                # `touch -h .direnv/flake-profile-*` glob also matches
                # flake-profile-<hash>.rc — the file use_flake watch_file()s.
                # Every load then invalidates every other consumer of the same
                # .envrc (extra terminals, `direnv exec`, the VS Code direnv
                # extension), which re-evaluate and touch it again, without
                # end. Fixed on master (#790, "Don't refresh gcroots"), not
                # yet released. Redefining the function after nix-direnv is
                # sourced is enough; angrr (above) keeps the GC roots alive.
                # Remove once nixpkgs ships a nix-direnv newer than 3.2.0.
                # (Patching the package instead does not work: its direnvrc is
                # resholved before patchPhase sees it, so the hunks miss.)
                direnvrcExtra = ''
                  _nix_refresh_gcroots() { :; }
                '';
              };
              fuse = {
                enable = true;
              };
              git = {
                enable = true;
                config.safe.directory = [ "/etc/nixos" ];
              };
              mosh = {
                enable = true;
              };
              nix-ld = {
                enable = true;
                libraries = with pkgs; [
                  alsa-lib
                  at-spi2-atk
                  at-spi2-core
                  bison
                  brotli
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
                  fuse3
                  gdk-pixbuf
                  glib
                  glibc
                  gperf
                  gtk3
                  gtk4
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
