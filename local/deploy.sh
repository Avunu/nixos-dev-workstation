#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage:"
  echo "  Remote deploy:  $0 remote <fqdn> <ip-address> [username]"
  echo "  Local install:  $0 local <disk-device> [username]"
  echo ""
  echo "Examples:"
  echo "  $0 remote dev-workstation.local 192.168.1.100 dylan"
  echo "  $0 local /dev/sda dylan"
  echo ""
  echo "Local mode is for running from a NixOS live boot disk to install"
  echo "onto the machine you're currently on."
  exit 1
}

MODE="${1:-}"
if [ -z "$MODE" ]; then
  usage
fi

get_agenix_key() {
  local key_file="./agenix-key"
  if [ -f "$key_file" ]; then
    echo "Found agenix key at $key_file"
    AGENIX_KEY="$(cat "$key_file")"
  else
    echo "No ./agenix-key file found."
    echo "Paste the age private key (starts with AGE-SECRET-KEY-), then press Enter:"
    read -r AGENIX_KEY
    if [ -z "$AGENIX_KEY" ]; then
      echo "ERROR: No key provided. The rclone bisync will not work without it."
      exit 1
    fi
    if [[ ! "$AGENIX_KEY" == AGE-SECRET-KEY-* ]]; then
      echo "WARNING: Key does not start with AGE-SECRET-KEY-. Proceeding anyway."
    fi
  fi
}

deploy_remote() {
  local FQDN="${1:-}"
  local IP_ADDRESS="${2:-}"
  local USERNAME="${3:-dylan}"

  if [ -z "$FQDN" ] || [ -z "$IP_ADDRESS" ]; then
    usage
  fi

  local HOSTNAME="${FQDN%%.*}"

  echo "Deploying NixOS Development Workstation to $FQDN (hostname: $HOSTNAME)"
  echo ""

  get_agenix_key

  local temp
  temp=$(mktemp -d)
  trap "rm -rf $temp" EXIT

  echo "Copying flake configuration to ${temp}/etc/nixos/..."
  mkdir -p "${temp}/etc/nixos"
  cp flake.nix "${temp}/etc/nixos/flake.nix"
  chmod 644 "${temp}/etc/nixos/flake.nix"

  echo "Setting up agenix key..."
  mkdir -p "${temp}/etc/agenix"
  echo "$AGENIX_KEY" > "${temp}/etc/agenix/key"
  chmod 600 "${temp}/etc/agenix/key"

  echo "Running nixos-anywhere..."
  nix run github:nix-community/nixos-anywhere -- \
    --extra-files "$temp" \
    --flake ".#${HOSTNAME}" \
    --target-host "root@${IP_ADDRESS}"

  echo ""
  echo "Deployment complete!"
  echo ""
  echo "To access the system:"
  echo "  ssh ${USERNAME}@${FQDN}"
}

deploy_local() {
  local DISK_DEVICE="${1:-}"
  local USERNAME="${2:-dylan}"

  if [ -z "$DISK_DEVICE" ]; then
    usage
  fi

  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Local install must be run as root (use sudo)."
    exit 1
  fi

  if [ ! -b "$DISK_DEVICE" ]; then
    echo "ERROR: $DISK_DEVICE is not a block device."
    exit 1
  fi

  echo "Installing NixOS Development Workstation locally to $DISK_DEVICE"
  echo "WARNING: This will ERASE $DISK_DEVICE completely."
  echo ""
  read -rp "Type 'yes' to continue: " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Aborted."
    exit 1
  fi
  echo ""

  get_agenix_key

  local HOSTNAME
  read -rp "Hostname for this machine: " HOSTNAME
  if [ -z "$HOSTNAME" ]; then
    echo "ERROR: Hostname is required."
    exit 1
  fi

  echo ""
  echo "Partitioning and formatting $DISK_DEVICE via disko..."

  # Generate a temporary flake that references the remote module with the correct disk device
  local build_dir
  build_dir=$(mktemp -d)
  trap 'rm -rf "$build_dir"' EXIT

  cp flake.nix "${build_dir}/flake.nix"

  # Update diskDevice in the flake to match the target
  sed -i "s|diskDevice = \"/dev/sda\"|diskDevice = \"${DISK_DEVICE}\"|" "${build_dir}/flake.nix"
  # Update hostname
  sed -i "s|hostName = \"dev-workstation\"|hostName = \"${HOSTNAME}\"|" "${build_dir}/flake.nix"
  # Update username
  sed -i "s|username = \"dylan\"|username = \"${USERNAME}\"|" "${build_dir}/flake.nix"

  # Run disko to partition and format
  nix run github:nix-community/disko -- \
    --mode disko \
    --flake "${build_dir}#${HOSTNAME}" \
    --arg disk "$DISK_DEVICE"

  echo "Building and installing NixOS..."
  nixos-install --flake "${build_dir}#${HOSTNAME}" --no-root-passwd

  # Place the agenix key and flake on the installed system
  echo "Installing agenix key..."
  mkdir -p /mnt/etc/agenix
  echo "$AGENIX_KEY" > /mnt/etc/agenix/key
  chmod 600 /mnt/etc/agenix/key

  echo "Installing flake configuration..."
  mkdir -p /mnt/etc/nixos
  cp "${build_dir}/flake.nix" /mnt/etc/nixos/flake.nix
  chmod 644 /mnt/etc/nixos/flake.nix

  echo ""
  echo "Installation complete! Remove the boot media and reboot."
  echo ""
  echo "  Hostname: $HOSTNAME"
  echo "  Username: $USERNAME"
  echo "  Password: password (change on first login)"
}

case "$MODE" in
  remote)
    shift
    deploy_remote "$@"
    ;;
  local)
    shift
    deploy_local "$@"
    ;;
  *)
    usage
    ;;
esac
