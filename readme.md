# nixos-dev-workstation

A reusable NixOS module for Avunu development workstations. Builds on top of [nixos-micro-desktop](https://github.com/Avunu/nixos-micro-desktop) and [rclone-nixos-module](https://github.com/Avunu/rclone-nixos-module) to provide a fully configured development environment deployable via [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) or a NixOS live boot disk.

## What's Included

-   **Desktop environment**: Full niri Wayland desktop via nixos-micro-desktop (DMS Shell, Nautilus, GNOME services, XDG portals, fonts, theming)
-   **Development tools**: VS Code, GitHub Desktop, Git, Bun, Docker Compose, Podman Desktop, nixfmt, Python with uv
-   **Productivity**: Google Chrome, LibreOffice, Obsidian, Inkscape, GIMP, VLC
-   **Containers**: Podman with Docker compatibility (dockerCompat + socket)
-   **File sync**: Incorporates the rclone bisync module for file share sync and mount
-   **Secrets**: Agenix is available for encrypted credentials (such as rclone config); the age key is optional and only needed once you add secrets
-   **SSH**: Bitwarden SSH agent socket pre-configured
-   **System management**: direnv + nix-direnv, nix-ld, AppImage support
-   **Nix**: [Determinate Nix](https://docs.determinate.systems/determinate-nix/) through its NixOS module; `determinate-nixd` runs the daemon (see [Determinate Nix](#determinate-nix))

## Repository Structure

```
nixos-dev-workstation/
├── flake.nix                # Module (nixosModules.devWorkstation), lib.mkHost, installers
└── local/
    ├── flake.nix            # Example /etc/nixos-style consumer configuration
    └── deploy.sh            # Deployment script (remote or local)
```

## Quick Start

### A new machine (recommended)

Each machine gets its own repository, which it then tracks. Make an empty
directory, run the wizard in it, and let it create the repository:

```bash
mkdir host-<name> && cd host-<name>
nix run github:Avunu/nixos-dev-workstation
```

The wizard asks the installer questions, then creates the repository, generates
the machine's agenix identity, commits, offers to push it to GitHub
(`Avunu/host-<name>`, private by default), and continues with the new
repository's own `nix run`: a network install (nixos-anywhere) or an offline
ISO. See [Managed from a host repo](#managed-from-a-host-repo).

### A one-off local install

Boot a NixOS live USB, connect to the internet, then:

```bash
sudo nix --experimental-features 'nix-command flakes' run github:Avunu/nixos-dev-workstation
```

The interactive installer will prompt for all configuration values (hostname, username, disk, SSH keys, etc.), partition the disk, install NixOS, and place the configuration at `/etc/nixos`. Reboot and you're done.

## Prerequisites

-   A machine with Nix installed (for remote deployment) or a NixOS live boot USB (for local installation)
-   (Optional) The age private key, only if you use agenix secrets
-   SSH access to the target machine (for remote deployment)
-   The target machine must be booted into a Linux environment accessible via SSH (remote) or directly (local)

## Configuration

### 1\. Create Your Local Flake

Copy `local/flake.nix` and customize it for your machine:

```nix
{
  # Where Determinate Nix is fetched from while the machine is still on
  # nixpkgs' Nix (the first switch, an installer). See "Determinate Nix".
  nixConfig = {
    extra-substituters = [ "https://install.determinate.systems" ];
    extra-trusted-public-keys = [ "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM=" ];
  };

  inputs = {
    nixpkgs.url = "github:numtide/nixpkgs-unfree?ref=nixos-unstable";
    nixos-dev-workstation = {
      url = "github:Avunu/nixos-dev-workstation";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-dev-workstation }:
    let
      hostName = "my-workstation";
      username = "myuser";
      system = "x86_64-linux";
    in {
      nixosConfigurations."${hostName}" = nixpkgs.lib.nixosSystem {
        system = system;
        modules = [
          { nix.nixPath = [ "nixpkgs=${self.inputs.nixpkgs}" ]; }
          nixos-dev-workstation.nixosModules.devWorkstation
          {
            devWorkstation = {
              hostName = hostName;
              diskDevice = "/dev/nvme0n1";        # Target disk
              bootMode = "uefi";              # "uefi" or "legacy"
              timeZone = "America/New_York";
              locale = "en_US.UTF-8";
              username = username;
              initialPassword = "password";   # Change on first login!
              sshKeys = [
                "ssh-ed25519 AAAA..."
              ];
              stateVersion = "25.11";
              enableVpn = false;
              extraPackages = with nixpkgs.legacyPackages.${system}; [
                # Additional packages for this specific machine
              ];
            };
          }
        ];
      };
    };
}
```

### 2\. Module Options

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| hostName | string | (required) | System hostname |
| diskDevice | string | /dev/nvme0n1 | Target disk for disko partitioning |
| bootMode | enum | "uefi" | "uefi" (systemd-boot) or "legacy" (GRUB) |
| timeZone | string | "America/New_York" | System timezone |
| locale | string | "en_US.UTF-8" | System locale |
| username | string | (required) | Primary user account name |
| initialPassword | string | "password" | Initial user password |
| sshKeys | list of strings | [] | SSH public keys for user and root |
| stateVersion | string | "25.11" | NixOS state version |
| extraPackages | list of packages | [] | Additional packages to install |
| enableVpn | bool | false | Enable NetworkManager VPN plugins |

## Deployment

### Interactive Installer (Recommended)

The primary way to deploy. Boot a NixOS live USB on the target machine, then:

```bash
# Connect to the internet
nmcli device wifi connect "SSID" password "password"
# Or for wired — should auto-connect

# Run the installer
sudo nix --experimental-features 'nix-command flakes' run github:Avunu/nixos-dev-workstation
```

The installer will:

1.  Prompt for hostname, username, password, timezone, locale, boot mode, disk, SSH keys, VPN, and (optionally) an agenix key
2.  Show a summary and ask for confirmation
3.  Partition and format the disk via disko
4.  Run `nixos-install`
5.  Place the flake (and the agenix key, if you provided one) on the installed system
6.  Tell you to remove the USB and reboot

### Remote Deployment (via nixos-anywhere)

Use this when deploying to a remote machine that's already booted into a Linux environment with SSH access (e.g., a NixOS installer ISO booted with SSH enabled, or an existing Linux installation).

```bash
cd local/
./deploy.sh remote <fqdn> <ip-address> [username]
```

**Example:**

```bash
./deploy.sh remote dev-workstation.local 192.168.1.100 developer
```

**What happens:**

1.  Copies `flake.nix` into a temporary directory.
2.  Runs `nixos-anywhere` which:
    -   SSHs into `root@<ip-address>`
    -   Partitions and formats the disk via disko
    -   Installs NixOS with your configuration
    -   Copies the extra files (the flake) onto the new system
3.  The machine reboots into the new NixOS installation.

No agenix key is needed. If you use agenix secrets, see [Secrets Management](#secrets-management) for providing one.

**Requirements:**

-   SSH root access to the target machine (password or key-based)
-   The target must be in a bootable Linux state (NixOS installer ISO is ideal)

### Local Deployment (via deploy.sh)

The `local/deploy.sh` script is an alternative for advanced use or scripted deployments:

```bash
# Remote (to a machine already running Linux with SSH)
cd local/
./deploy.sh remote <fqdn> <ip-address> [username]

# Local (from NixOS live boot, requires customized local/flake.nix)
sudo ./deploy.sh local <disk-device> [username]
```

### Preparing a NixOS Live USB

Download the NixOS minimal ISO from [https://nixos.org/download](https://nixos.org/download) and write it to a USB:

```bash
sudo dd if=nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress
```

Boot from it, connect to the internet, and run the installer command from Quick Start above.

## Determinate Nix

The module imports Determinate's NixOS module, so every machine runs
[Determinate Nix](https://docs.determinate.systems/determinate-nix/) with
`determinate-nixd` as the daemon. `determinate-nixd` owns `/etc/nix/nix.conf`;
what NixOS generates from `nix.settings` (here, in nixos-micro-desktop and in
your own flake) lands in `/etc/nix/nix.custom.conf`, which it includes. Its own
`extra-substituters` and `extra-experimental-features` come after that include,
so your settings add to them rather than replace them. The Nix version follows
the `determinate` input's lock, not nixpkgs'. `determinate.enable = false`
turns it off.

`nixpkgs#foo` and `<nixpkgs>` still resolve to the nixpkgs the system was built
from. Determinate would point them at its own weekly nixpkgs tarball; the
override in `flake.nix` keeps the previous behaviour, and deleting it takes
Determinate's.

### Moving an existing machine to Determinate Nix

Determinate Nix comes from `install.determinate.systems`, not `cache.nixos.org`,
and a machine still on nixpkgs' Nix does not know that cache yet. Do the first
switch by hand with it named, so the daily `system-upgrade` does not compile
Nix on its own:

```bash
sudo nixos-rebuild switch --flake <flake> \
  --option extra-substituters https://install.determinate.systems \
  --option extra-trusted-public-keys cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM=
```

`<flake>` is `/etc/nixos`, or the host repo's flake reference for a machine
managed from one. After that `determinate-nixd` adds the cache itself, so
nothing more is needed, including for later Determinate Nix upgrades. Building
this flake from somewhere that is not on Determinate yet (`nix run`,
`nix build .#installerIso`) needs the same two options; the flake's
`nixConfig` offers them, and `--accept-flake-config` accepts them without the
prompt. A host repo's own flake needs its own `nixConfig` for the same reason.

`determinate-nixd login` is only for FlakeHub Cache and private flakes.

## Secrets Management

### The Agenix Key

A host repository always has one: the bootstrap generates it and keeps it as
`secrets/key.age`, encrypted to the operators only, and every install path
writes it to `/etc/agenix/key` (see [Managed from a host repo](#managed-from-a-host-repo)).

For a local (`/etc/nixos`) install the age private key is **optional**. The module does not declare any `age.secrets` itself, so the agenix module stays disabled and a machine installs, boots and updates without a key. You only need one once you add secrets (see [Adding More Secrets](#adding-more-secrets)); a machine that declares secrets but has no key will fail to decrypt them at activation.

When used, the key lives at `/etc/agenix/key` (mode `0400`) and decrypts secrets at system activation time. It should be stored securely (e.g., in Bitwarden) and corresponds to one of the public keys listed in `secrets.nix`.

**Providing the key:**

-   **Interactive / unattended installer:** export it as `agenix__key` (for example via an agenix-shell devShell), or answer the "Provide asset 'agenix-key'?" prompt in the guided installer. Skip it and the install proceeds without one.
-   **`deploy.sh` or an existing machine:** copy it into place yourself:

    ```bash
    sudo install -D -m 0400 agenix-key /etc/agenix/key
    ```

### Creating/Editing Secrets

To create or re-encrypt the rclone secret:

```bash
# From the repo root (requires one of the private keys in secrets.nix)
nix run github:ryantm/agenix -- -e secrets/rclone.age
```

This opens your `$EDITOR` with the decrypted content. Paste your rclone configuration (the `[vivobox]` remote definition) and save.

### Adding More Secrets

1.  Add the secret definition to `secrets.nix`:
    
    ```nix
    "secrets/my-secret.age".publicKeys = allKeys;
    ```
    
2.  Create the encrypted file:
    
    ```bash
    nix run github:ryantm/agenix -- -e secrets/my-secret.age
    ```
    
3.  Reference it in `flake.nix`:
    
    ```nix
    age.secrets.my-secret.file = ./secrets/my-secret.age;
    ```
    

## Managed from a host repo

This is the default for a new machine: instead of a local `/etc/nixos`, it
lives in its own repository and tracks it. Push to the default branch and its
daily `system-upgrade` switches to the new configuration. The repository's
`flake.lock` decides every version, so update it there, never on the machine.

```bash
mkdir host-<name> && cd host-<name>
nix run github:Avunu/nixos-dev-workstation    # creates the repo, then installs
```

The bootstrap (also `nix run github:Avunu/nixos-dev-workstation#bootstrap`),
the template it writes and `lib.mkHost` come from
[nixos-install-helper](https://github.com/Avunu/nixos-install-helper); this
flake's `lib.mkHost` is that function with `devWorkstation` filled in. A new
repository holds:

| File | What it holds |
| --- | --- |
| `flake.nix` | one `nixos-dev-workstation.lib.mkHost` call with `repo = "github:<owner>/<repo>"` |
| `devWorkstation-settings.json` | the installer's answers |
| `host.nix` | anything else for this machine |
| `secrets.nix` | who can decrypt each secret |
| `secrets/key.age` | the machine's **agenix identity**, freshly generated, encrypted to the operators only |
| `secrets/github-token.age` | a read-only GitHub token (private repos), encrypted to the operators and the identity |

The operators are the SSH keys in the settings (`sshKeys`) plus the standing
admins in `adminKeys` in this repository's `flake.nix`. The machine never
decrypts with its SSH host key: entering the repository's devShell (direnv
`use flake`) decrypts `secrets/key.age` into `$agenix__key` with your SSH key,
the wizard does the same without it, and every install path (`nix run`,
`.#deploy`, `.#installerIso`) carries it to `/etc/agenix/key`. A reinstall onto
a new disk therefore decrypts the same secrets without re-keying anything.

The token is a fine-grained PAT with **Contents: read-only** on the host repo.
On the machine agenix decrypts it and nix `!include`s it as `access-tokens`
(`installHelper.githubTokenFile`); git gets it through a credential helper. It
never enters the Nix store. Flake input updates arrive as dependabot pull
requests, merged once the configuration still evaluates.

Repositories made by the older `new-host` app (which called nixos-install-helper's
`mkProject` with `flakeStyle = "repo"` directly) keep working unchanged.

## Post-Installation

### First Login

-   Username and password are what you configured (`initialPassword`, default: `password`)
-   **Change your password immediately:** `passwd`

### Auto-Updates

The system automatically:

-   Updates flake inputs hourly (`flake-update.timer`)
-   Rebuilds and switches via `system.autoUpgrade`
-   Reboots if needed between 01:00-05:00

To manually update:

```bash
sudo nixos-rebuild switch --flake /etc/nixos --impure
```

### Rclone Bisync

The `vivobox:client` remote syncs bidirectionally to `~/Clients` on a 15-minute interval (default from rclone-nixos-module). The first sync after deployment may require a `--resync` flag — check the service logs:

```bash
systemctl --user status rclone-bisync-clients
journalctl --user -u rclone-bisync-clients
```

If the first sync fails with a "bisync requires --resync" error, run once manually:

```bash
rclone bisync ~/Clients vivobox:client --config /run/agenix/rclone --resync
```

## Customizing Per-Machine

The `local/flake.nix` is meant to be customized per deployment. Common overrides:

```nix
{
  devWorkstation = {
    diskDevice = "/dev/nvme0n1";   # NVMe drive
    bootMode = "legacy";           # Older BIOS machine
    enableVpn = true;              # Install VPN plugins
    extraPackages = with pkgs; [
      thunderbird
      slack
    ];
  };

  # Override anything from the module
  networking.firewall.enable = true;
  services.printing.enable = false;
}
```
