#!/bin/bash

# This script automates the creation of a Debian 13 virtual machine using libvirt and cloud-init.
# Features:
#   - Downloads a Debian 13 cloud image (or uses a specified URL)
#   - Creates a per-VM disk and cloud-init seed ISO in configurable directories
#   - Supports user, SSH key, hostname, memory, CPU, disk size, and network customization
#   - Optionally deletes/recreates existing VMs and logs in after setup
#   - Supports both system and user libvirt sessions
#
# Usage:
#   See the usage() function or run with -? for all options and defaults.
#
# Requirements:
#   - virt-install, cloud-localds, qemu-img, wget, virsh
#   - libvirt and KVM support
#
# Author: Stefan Haun <mail@tuxathome.de>
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSES/MIT.txt

set -e

delete_vm() {
  local vmname="$1"
  local libvirt_uri="$2"
  local vm_img="$3"
  local seed_img="$4"

  echo
  echo "🔥🔥🔥 Deleting VM $vmname ...  🔥🔥🔥"
  echo

  virsh --connect "$libvirt_uri" destroy "$vmname" 2>/dev/null || true
  virsh --connect "$libvirt_uri" undefine "$vmname" --remove-all-storage --nvram 2>/dev/null || true
  rm -f "$vm_img" "$seed_img"
}

# Check for required tools
for tool in virt-install cloud-localds qemu-img wget; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "❌ Error: Required tool '$tool' is not installed or not in PATH."
    exit 10
  fi
done

usage() {
  echo "Usage: $0 -u <username> -k <ssh_pubkey_file> -h <hostname.domain> [-m <memory_mb>] [-c <cpus>] [-s <disk_gb>] [-n <network>] [-S <session>] [-f] [-l] [-d <download_dir>] [-i <vm_dir>] [-U <image_url>] -r"
  echo "  -u   Username for the VM"
  echo "  -k   SSH public key file (default: \$HOME/.ssh/id_rsa.pub)"
  echo "  -h   Hostname (FQDN, e.g., vm01.example.com)"
  echo "  -m   Memory in MB (default: 2048)"
  echo "  -c   CPUs (default: 2)"
  echo "  -s   Disk size in GB (default: 10)"
  echo "  -n   Libvirt network (default: default)"
  echo "  -S   Libvirt session: 'system' (default) or 'user' or full URI"
  echo "  -f   Force delete and recreate VM if it exists"
  echo "  -l   SSH into the VM after setup"
  echo "  -d   Directory to store the downloaded base image (default: current directory)"
  echo "  -i   Directory to store per-VM disk and seed ISO files (default: current directory)"
  echo "  -U   Download URL for the Debian cloud image (default: $IMG_URL)"
  echo "  -r   Remove the VM after SSH session exits"
  exit 1
}

IMG_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"

PUBKEY_FILE="$HOME/.ssh/id_rsa.pub"
MEMORY=2048
CPUS=2
DISK_SIZE=10
NETWORK=default
SESSION=system
FORCE=0
LOGIN=0
DOWNLOAD_DIR=$(pwd)
VM_DIR=$(pwd)
REMOVE_ON_EXIT=0

while getopts "u:k:h:m:c:s:n:S:fld:i:U:r" opt; do
  case $opt in
    u) VMUSER="$OPTARG" ;;
    k) PUBKEY_FILE="$OPTARG" ;;
    h) FQDN="$OPTARG" ;;
    m) MEMORY="$OPTARG" ;;
    c) CPUS="$OPTARG" ;;
    s) DISK_SIZE="$OPTARG" ;;
    n) NETWORK="$OPTARG" ;;
    S) SESSION="$OPTARG" ;;
    f) FORCE=1 ;;
    l) LOGIN=1 ;;
    d) DOWNLOAD_DIR="$OPTARG" ;;
    i) VM_DIR="$OPTARG" ;;
    U) IMG_URL="$OPTARG" ;;
    r) REMOVE_ON_EXIT=1 ;;
    *) usage ;;
  esac
done

if [ -z "$VMUSER" ] || [ -z "$FQDN" ]; then
  usage
fi

if [ ! -f "$PUBKEY_FILE" ]; then
  echo "❌ Error: SSH public key file $PUBKEY_FILE not found."
  exit 2
fi

# Map session shortcut to URI
case "$SESSION" in
  system) LIBVIRT_URI="qemu:///system" ;;
  user)   LIBVIRT_URI="qemu:///session" ;;
  *)      LIBVIRT_URI="$SESSION" ;;
esac

PUBKEY=$(cat "$PUBKEY_FILE")
VMNAME="${FQDN%%.*}"

# Paths
IMG_LOCAL="$DOWNLOAD_DIR/debian-13-genericcloud-amd64.qcow2"
VM_IMG="$VM_DIR/${VMNAME}-vm.qcow2"
SEED_IMG="$VM_DIR/${VMNAME}-seed.iso"

# Check if the specified network exists
if ! virsh --connect "$LIBVIRT_URI" net-list --all --name | grep -wq "$NETWORK"; then
  echo "❌ Error: Network '$NETWORK' does not exist."
  echo "Available networks:"
  virsh --connect "$LIBVIRT_URI" net-list --all --name
  exit 4
fi

# Check for existing VM name
if virsh --connect "$LIBVIRT_URI" list --all --name | grep -wq "$VMNAME"; then
  if [ "$FORCE" -eq 1 ]; then
    delete_vm "$VMNAME" "$LIBVIRT_URI" "$VM_IMG" "$SEED_IMG"
  else
    echo "❌ Error: A VM named $VMNAME already exists. Use -f to force deletion."
    exit 3
  fi
fi

# Download Debian 13 cloud image if needed
IMG_LOCAL="$DOWNLOAD_DIR/debian-13-genericcloud-amd64.qcow2"
if [ ! -f "$IMG_LOCAL" ]; then
  echo "Downloading Debian 13 cloud image..."
  wget -O "$IMG_LOCAL" "$IMG_URL"
fi

# Create a working copy of the cloud image
cp "$IMG_LOCAL" "$VM_IMG"
qemu-img resize -f qcow2 "$VM_IMG" "${DISK_SIZE}G"

# Create temp dir for intermediate files
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Create cloud-init user-data
# https://cloudinit.readthedocs.io/en/latest/explanation/about-cloud-config.html
cat > "$TMPDIR/user-data" <<EOF
#cloud-config
hostname: $VMNAME
fqdn: $FQDN
preserve_hostname: false

users:
  - name: $VMUSER
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    ssh-authorized-keys:
      - $PUBKEY
    lock_passwd: true
    passwd: "*"

ssh_pwauth: false

disable_root: false

package_update: true
package_upgrade: true

packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable --now qemu-guest-agent
EOF

cat > "$TMPDIR/meta-data" <<EOF
instance-id: $VMNAME
local-hostname: $FQDN
EOF

cloud-localds "${SEED_IMG}" "$TMPDIR/user-data" "$TMPDIR/meta-data"

# Create the VM
virt-install \
  --connect "$LIBVIRT_URI" \
  --name "$VMNAME" \
  --memory "$MEMORY" \
  --vcpus "$CPUS" \
  --cpu host-passthrough \
  --machine q35 \
  --disk path="$VM_IMG",format=qcow2,boot_order=1 \
  --disk path="$SEED_IMG",device=cdrom,boot_order=2 \
  --os-variant=debian13 \
  --network network="$NETWORK",model=virtio \
  --virt-type=kvm \
  --console pty,target_type=serial \
  --import \
  --noautoconsole

# Wait for the VM to get an IP address
echo "Waiting for $VMNAME to obtain an IP address..."
# shellcheck disable=SC2034
for i in {1..150}; do
  VM_IP=$(virsh --connect "$LIBVIRT_URI" domifaddr "$VMNAME" --source agent 2>/dev/null | awk '/ipv4/ && $4 !~ /^127\./ {print $4}' | cut -d/ -f1)
  if [ -n "$VM_IP" ]; then
    echo "✅"
    echo "VM IPv4 address: $VM_IP"
    break
  fi
  echo -n "⏳"
  sleep 1
done

if [ -z "$VM_IP" ]; then
  echo "❌ Failed to obtain VM IPv4 address after waiting."
  exit 5
fi

echo "✅ VM $VMNAME created successfully."

if [ "$LOGIN" -eq 1 ]; then
  echo "Connecting to $VMUSER@$VM_IP ..."
  echo
  echo
  echo "🐧🐧🐧  You are now entering a different VM!  🐧🐧🐧"
  echo
  echo

  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$VMUSER@$VM_IP"

  if [ "$REMOVE_ON_EXIT" -eq 1 ]; then
    delete_vm "$VMNAME" "$LIBVIRT_URI" "$VM_IMG" "$SEED_IMG"
  fi
fi
