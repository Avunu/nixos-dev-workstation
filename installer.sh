#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}::${NC} $*"; }
success() { echo -e "${GREEN}::${NC} $*"; }
error() { echo -e "${RED}ERROR:${NC} $*" >&2; }
header() { echo -e "\n${BOLD}$*${NC}\n"; }

# Check root
if [ "$(id -u)" -ne 0 ]; then
  error "This installer must be run as root."
  echo "  sudo nix run github:Avunu/nixos-dev-workstation"
  exit 1
fi

header "Avunu Development Workstation Installer"
echo "This will install NixOS with the Avunu dev workstation configuration."
echo "All data on the target disk will be erased."
echo ""

# --- Gather inputs ---

# Hostname
read -rp "Hostname: " HOSTNAME
if [ -z "$HOSTNAME" ]; then
  error "Hostname is required."
  exit 1
fi

# Username
read -rp "Username [developer]: " USERNAME
USERNAME="${USERNAME:-developer}"

# Initial password
read -rp "Initial password [password]: " INITIAL_PASSWORD
INITIAL_PASSWORD="${INITIAL_PASSWORD:-password}"

# Timezone
read -rp "Timezone [America/New_York]: " TIMEZONE
TIMEZONE="${TIMEZONE:-America/New_York}"

# Locale
read -rp "Locale [en_US.UTF-8]: " LOCALE
LOCALE="${LOCALE:-en_US.UTF-8}"

# Boot mode
echo ""
info "Boot mode:"
echo "  1) uefi (modern systems, systemd-boot)"
echo "  2) legacy (older BIOS systems, GRUB)"
read -rp "Select [1]: " BOOT_CHOICE
case "${BOOT_CHOICE:-1}" in
  1) BOOT_MODE="uefi" ;;
  2) BOOT_MODE="legacy" ;;
  *) BOOT_MODE="uefi" ;;
esac

# Disk device
echo ""
info "Available block devices:"
lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -E "disk"
echo ""
read -rp "Target disk device [/dev/nvme0n1]: " DISK_DEVICE
DISK_DEVICE="${DISK_DEVICE:-/dev/nvme0n1}"

if [ ! -b "$DISK_DEVICE" ]; then
  error "$DISK_DEVICE is not a block device."
  exit 1
fi

# SSH keys
echo ""
info "SSH public keys (one per line, empty line to finish):"
SSH_KEYS=()
while true; do
  read -rp "  Key: " key
  if [ -z "$key" ]; then
    break
  fi
  SSH_KEYS+=("$key")
done

# VPN
read -rp "Enable VPN support? [y/N]: " VPN_CHOICE
case "${VPN_CHOICE}" in
  [yY]*) ENABLE_VPN="true" ;;
  *) ENABLE_VPN="false" ;;
esac

# Agenix key
echo ""
info "Agenix private key (for rclone secret decryption)."
echo "  This key starts with AGE-SECRET-KEY-..."
read -rp "  Paste key (or leave empty to skip): " AGENIX_KEY
if [ -n "$AGENIX_KEY" ] && [[ ! "$AGENIX_KEY" == AGE-SECRET-KEY-* ]]; then
  echo "  WARNING: Key does not look like an age secret key."
fi

# State version
STATE_VERSION="25.11"

# --- Confirmation ---

header "Configuration Summary"
echo "  Hostname:     $HOSTNAME"
echo "  Username:     $USERNAME"
echo "  Timezone:     $TIMEZONE"
echo "  Locale:       $LOCALE"
echo "  Boot mode:    $BOOT_MODE"
echo "  Disk:         $DISK_DEVICE"
echo "  SSH keys:     ${#SSH_KEYS[@]} key(s)"
echo "  VPN:          $ENABLE_VPN"
echo "  Agenix key:   $([ -n "$AGENIX_KEY" ] && echo "provided" || echo "skipped")"
echo ""
echo -e "  ${RED}WARNING: $DISK_DEVICE will be completely erased!${NC}"
echo ""
read -rp "Proceed with installation? (type 'yes'): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 1
fi

# --- Generate flake.nix ---

header "Generating configuration..."

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

# Build SSH keys nix list
SSH_KEYS_NIX=""
for key in "${SSH_KEYS[@]}"; do
  SSH_KEYS_NIX+="
                  \"${key}\""
done

cat > "${BUILD_DIR}/flake.nix" << FLAKE
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
      hostName = "${HOSTNAME}";
      username = "${USERNAME}";
      system = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        "\${hostName}" = nixpkgs.lib.nixosSystem {
          system = system;
          modules = [
            { nix.nixPath = [ "nixpkgs=\${self.inputs.nixpkgs}" ]; }
            nixos-dev-workstation.nixosModules.devWorkstation
            {
              devWorkstation = {
                hostName = hostName;
                diskDevice = "${DISK_DEVICE}";
                bootMode = "${BOOT_MODE}";
                timeZone = "${TIMEZONE}";
                locale = "${LOCALE}";
                username = username;
                initialPassword = "${INITIAL_PASSWORD}";
                sshKeys = [${SSH_KEYS_NIX}
                ];
                stateVersion = "${STATE_VERSION}";
                enableVpn = ${ENABLE_VPN};
              };
            }
          ];
        };
      };
    };
}
FLAKE

info "Generated flake.nix at ${BUILD_DIR}/flake.nix"

# --- Partition and install ---

header "Partitioning ${DISK_DEVICE}..."

nix run github:nix-community/disko \
  --experimental-features "nix-command flakes" -- \
  --mode disko \
  --flake "${BUILD_DIR}#${HOSTNAME}" \

header "Installing NixOS..."

nixos-install --flake "${BUILD_DIR}#${HOSTNAME}" --no-root-passwd

# --- Post-install: place files on the new system ---

header "Configuring installed system..."

# Flake config
info "Installing flake to /mnt/etc/nixos/..."
mkdir -p /mnt/etc/nixos
cp "${BUILD_DIR}/flake.nix" /mnt/etc/nixos/flake.nix
chmod 644 /mnt/etc/nixos/flake.nix

# Agenix key
if [ -n "$AGENIX_KEY" ]; then
  info "Installing agenix key to /mnt/etc/agenix/..."
  mkdir -p /mnt/etc/agenix
  echo "$AGENIX_KEY" > /mnt/etc/agenix/key
  chmod 600 /mnt/etc/agenix/key
else
  echo ""
  echo "  NOTE: No agenix key was provided."
  echo "  Place it manually at /etc/agenix/key after first boot"
  echo "  for rclone bisync to work."
fi

# --- Done ---

header "Installation complete!"
echo ""
success "Remove the boot media and reboot into your new system."
echo ""
echo "  Hostname:  $HOSTNAME"
echo "  Username:  $USERNAME"
echo "  Password:  $INITIAL_PASSWORD (change with 'passwd' after login)"
echo ""
echo "  After reboot, the system will auto-update hourly from:"
echo "    /etc/nixos/flake.nix"
echo ""
