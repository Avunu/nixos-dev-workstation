# nixos-dev-workstation

A reusable NixOS module for Avunu development workstations. Builds on top of [nixos-micro-desktop](https://github.com/Avunu/nixos-micro-desktop) and [rclone-nixos-module](https://github.com/Avunu/rclone-nixos-module) to provide a fully configured development environment deployable via [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) or a NixOS live boot disk.

## What's Included

- **Desktop environment**: Full niri Wayland desktop via nixos-micro-desktop (DMS Shell, Nautilus, GNOME services, XDG portals, fonts, theming)
- **Development tools**: VS Code, GitHub Desktop, Git, Bun, Docker Compose, Podman Desktop, nixfmt, Python with uv
- **Productivity**: Google Chrome, LibreOffice, Obsidian, Inkscape, GIMP, VLC
- **Containers**: Podman with Docker compatibility (dockerCompat + socket)
- **File sync**: Bidirectional sync from `vivobox:client` to `~/Clients` via rclone bisync
- **Secrets**: Agenix for encrypted credentials (rclone config)
- **SSH**: Bitwarden SSH agent socket pre-configured
- **System management**: direnv + nix-direnv, nix-ld, AppImage support, auto-upgrade with hourly flake updates

## Repository Structure

```
nixos-dev-workstation/
├── flake.nix          # Module definition (nixosModules.devWorkstation)
├── secrets.nix        # Agenix public key definitions
├── secrets/
│   └── rclone.age     # Encrypted rclone credentials
└── local/
    ├── flake.nix      # Example consumer configuration (customize per machine)
    ├── deploy.sh      # Deployment script (remote or local)
    └── agenix-key     # (optional) Age private key for deployment
```

## Prerequisites

- A machine with Nix installed (for remote deployment) or a NixOS live boot USB (for local installation)
- The age private key for decrypting secrets
- SSH access to the target machine (for remote deployment)
- The target machine must be booted into a Linux environment accessible via SSH (remote) or directly (local)

## Configuration

### 1. Create Your Local Flake

Copy `local/flake.nix` and customize it for your machine:

```nix
{
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
              diskDevice = "/dev/sda";        # Target disk
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

### 2. Module Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `hostName` | string | (required) | System hostname |
| `diskDevice` | string | `/dev/sda` | Target disk for disko partitioning |
| `bootMode` | enum | `"uefi"` | `"uefi"` (systemd-boot) or `"legacy"` (GRUB) |
| `timeZone` | string | `"America/New_York"` | System timezone |
| `locale` | string | `"en_US.UTF-8"` | System locale |
| `username` | string | (required) | Primary user account name |
| `initialPassword` | string | `"password"` | Initial user password |
| `sshKeys` | list of strings | `[]` | SSH public keys for user and root |
| `stateVersion` | string | `"25.11"` | NixOS state version |
| `extraPackages` | list of packages | `[]` | Additional packages to install |
| `enableVpn` | bool | `false` | Enable NetworkManager VPN plugins |

## Deployment

### Remote Deployment (via nixos-anywhere)

Use this when deploying to a remote machine that's already booted into a Linux environment with SSH access (e.g., a NixOS installer ISO booted with SSH enabled, or an existing Linux installation).

```bash
cd local/
./deploy.sh remote <fqdn> <ip-address> [username]
```

**Example:**
```bash
./deploy.sh remote dev-workstation.local 192.168.1.100 dylan
```

**What happens:**
1. The script looks for `./agenix-key`. If not found, it prompts you to paste the age private key.
2. Copies `flake.nix` and the agenix key into a temporary directory.
3. Runs `nixos-anywhere` which:
   - SSHs into `root@<ip-address>`
   - Partitions and formats the disk via disko
   - Installs NixOS with your configuration
   - Copies the extra files (flake + key) onto the new system
4. The machine reboots into the new NixOS installation.

**Requirements:**
- SSH root access to the target machine (password or key-based)
- The target must be in a bootable Linux state (NixOS installer ISO is ideal)

### Local Deployment (from NixOS Live Boot)

Use this when you're physically at the machine, booted from a NixOS live USB.

```bash
# Boot the NixOS installer USB
# Connect to the internet (nmtui or nmcli)
# Clone or copy the local/ directory to the live system

sudo ./deploy.sh local <disk-device> [username]
```

**Example:**
```bash
sudo ./deploy.sh local /dev/nvme0n1 dylan
```

**What happens:**
1. Prompts for the age private key (or reads `./agenix-key`).
2. Asks for the hostname.
3. Confirms before erasing the disk (you must type `yes`).
4. Runs disko to partition and format the target disk.
5. Runs `nixos-install` to build and install the system to `/mnt`.
6. Places the agenix key at `/mnt/etc/agenix/key`.
7. Places the flake config at `/mnt/etc/nixos/flake.nix`.
8. You remove the USB and reboot.

**Requirements:**
- Booted from a NixOS live USB (minimal or graphical)
- Internet connection (to fetch flake inputs and Nix store paths)
- Run as root (`sudo`)

### Preparing a NixOS Live USB

Download the NixOS minimal ISO from https://nixos.org/download and write it to a USB:

```bash
# From any Linux machine
sudo dd if=nixos-minimal-*.iso of=/dev/sdX bs=4M status=progress
```

Boot from the USB, then:

```bash
# Connect to WiFi (if needed)
sudo systemctl start wpa_supplicant
nmcli device wifi connect "SSID" password "password"

# Or for wired, it should auto-connect via DHCP

# Enable nix flakes in the live environment
export NIX_CONFIG="experimental-features = nix-command flakes"

# Get the deploy script onto the machine (clone, scp, or USB)
nix-shell -p git
git clone https://github.com/Avunu/nixos-dev-workstation.git
cd nixos-dev-workstation/local

# Run the local installer
sudo ./deploy.sh local /dev/nvme0n1 dylan
```

## Secrets Management

### The Agenix Key

Each deployed machine needs the age private key at `/etc/agenix/key`. This key is used at system activation time to decrypt secrets (currently just the rclone config).

**Where to get the key:** The age private key should be stored securely (e.g., in Bitwarden). It corresponds to one of the public keys listed in `secrets.nix`.

**Providing the key during deployment:**
- **Option A:** Place it as `local/agenix-key` before running `deploy.sh` (the file is gitignored)
- **Option B:** Paste it interactively when the deploy script prompts

### Creating/Editing Secrets

To create or re-encrypt the rclone secret:

```bash
# From the repo root (requires one of the private keys in secrets.nix)
nix run github:ryantm/agenix -- -e secrets/rclone.age
```

This opens your `$EDITOR` with the decrypted content. Paste your rclone configuration (the `[vivobox]` remote definition) and save.

### Adding More Secrets

1. Add the secret definition to `secrets.nix`:
   ```nix
   "secrets/my-secret.age".publicKeys = allKeys;
   ```
2. Create the encrypted file:
   ```bash
   nix run github:ryantm/agenix -- -e secrets/my-secret.age
   ```
3. Reference it in `flake.nix`:
   ```nix
   age.secrets.my-secret.file = ./secrets/my-secret.age;
   ```

## Post-Installation

### First Login

- Username and password are what you configured (`initialPassword`, default: `password`)
- **Change your password immediately:** `passwd`

### Auto-Updates

The system automatically:
- Updates flake inputs hourly (`flake-update.timer`)
- Rebuilds and switches via `system.autoUpgrade` 
- Reboots if needed between 01:00-05:00

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
