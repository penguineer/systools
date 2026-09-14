#!/bin/sh

# Create and validate a recovery snapshot from an OpenWrt router.
#
# Usage:
#   openwrt-backup <router-target> <backup-directory>
#
# Example:
#   openwrt-backup root@router "/Vault/Backup/Router"
#
# A timestamped snapshot directory is created below <backup-directory>.
# The final directory appears only after the snapshot has been validated.

set -eu

usage() {
    echo "Usage: $0 <router-target> <backup-directory>" >&2
    exit 2
}

[ "$#" -eq 2 ] || usage

TARGET=$1
BACKUP_ROOT=$2

[ -n "$TARGET" ] || usage
[ -n "$BACKUP_ROOT" ] || usage

# Backup contents may contain credentials and other secrets.
umask 077

STAMP=$(date '+%Y-%m-%d_%H%M%S')
DEST="$BACKUP_ROOT/router-$STAMP"
WORK="$BACKUP_ROOT/.router-$STAMP.partial"

mkdir -p "$BACKUP_ROOT"

if [ -e "$WORK" ] || [ -e "$DEST" ]; then
    echo "ERROR: snapshot path already exists:" >&2
    echo "  $WORK" >&2
    echo "  $DEST" >&2
    exit 1
fi

mkdir "$WORK"

ssh_router() {
    ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=10 \
        -o ConnectionAttempts=1 \
        "$TARGET" "$@"
}

fail() {
    echo "ERROR: $1" >&2
    echo "Partial data retained at: $WORK" >&2
    exit 1
}

printf '%s\n' "Creating OpenWrt configuration backup from $TARGET ..."
if ! ssh_router 'sysupgrade -k -b -' > "$WORK/openwrt-backup.tar.gz"; then
    fail "OpenWrt backup command failed"
fi

[ -s "$WORK/openwrt-backup.tar.gz" ] || fail "backup archive is empty"

printf '%s\n' "Validating backup archive ..."
if ! tar -tzf "$WORK/openwrt-backup.tar.gz" > "$WORK/archive-contents.txt"; then
    fail "backup archive is not a readable tar.gz"
fi

# Minimal recovery sanity checks. These do not attempt to define the complete
# OpenWrt backup contents; they catch an obviously unusable snapshot.
grep -qxF 'etc/config/network' "$WORK/archive-contents.txt" \
    || fail "backup does not contain etc/config/network"
grep -qxF 'etc/config/firewall' "$WORK/archive-contents.txt" \
    || fail "backup does not contain etc/config/firewall"
grep -qxF 'etc/backup/installed_packages.txt' "$WORK/archive-contents.txt" \
    || fail "backup does not contain installed package metadata"

printf '%s\n' "Collecting sysupgrade file list ..."
if ! ssh_router 'sysupgrade -l' > "$WORK/sysupgrade-file-list.txt"; then
    fail "could not collect sysupgrade file list"
fi

printf '%s\n' "Collecting system inventory ..."
if ! ssh_router '
    echo "=== DATE ==="
    date "+%Y-%m-%dT%H:%M:%S%z"
    echo

    echo "=== BOARD ==="
    ubus call system board
    echo

    echo "=== RELEASE ==="
    cat /etc/openwrt_release
    echo

    echo "=== KERNEL ==="
    uname -a
    echo

    echo "=== FILESYSTEM ==="
    df -h
    echo

    echo "=== PACKAGES ==="
    if command -v apk >/dev/null 2>&1; then
        apk list --installed
    elif command -v opkg >/dev/null 2>&1; then
        opkg list-installed
    else
        echo "No supported package manager found"
    fi
    echo

    echo "=== NETWORK ADDRESSES ==="
    ip addr
    echo

    echo "=== IPV4 ROUTES ==="
    ip route
    echo

    echo "=== IPV6 ROUTES ==="
    ip -6 route
' > "$WORK/system-inventory.txt"; then
    fail "could not collect system inventory"
fi

printf '%s\n' "Collecting UCI configuration ..."
if ! ssh_router 'uci export' > "$WORK/uci-export.txt"; then
    fail "could not collect UCI configuration"
fi

printf '%s\n' "$TARGET" > "$WORK/router-target.txt"

printf '%s\n' "Calculating checksums ..."
if ! (
    cd "$WORK"
    sha256sum \
        openwrt-backup.tar.gz \
        archive-contents.txt \
        sysupgrade-file-list.txt \
        system-inventory.txt \
        uci-export.txt \
        router-target.txt \
        > SHA256SUMS

    sha256sum -c SHA256SUMS
); then
    fail "checksum verification failed"
fi

# WORK and DEST are deliberately below the same parent, so this rename publishes
# the already validated snapshot without exposing a half-built final directory.
if ! mv "$WORK" "$DEST"; then
    fail "could not publish validated snapshot"
fi

printf '\nSnapshot completed successfully:\n%s\n' "$DEST"
