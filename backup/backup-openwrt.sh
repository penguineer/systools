#!/bin/sh

# Create and validate a recovery snapshot from an OpenWrt router.
#
# Usage:
#   backup-openwrt.sh <router-target> <backup-directory>
#
# Example:
#   backup-openwrt.sh root@router "/var/backups/openwrt/router"
#
# A timestamped snapshot directory is created below <backup-directory>.
# The final directory appears only after the snapshot has been validated.
#
# Local requirements:
#   - POSIX shell
#   - ssh
#   - tar with gzip support
#   - grep
#   - sha256sum, or shasum with SHA-256 support
#
# Remote requirements:
#   - OpenWrt
#   - sysupgrade
#   - uci
#   - ubus
#   - ip
#
# The installed package inventory supports both apk and opkg when available.

set -eu

PROG=${0##*/}

usage() {
    echo "Usage: $PROG <router-target> <backup-directory>" >&2
    exit 2
}

error() {
    echo "ERROR: $*" >&2
}

require_local_command() {
    command -v "$1" >/dev/null 2>&1 || {
        error "required local command not found: $1"
        exit 1
    }
}

[ "$#" -eq 2 ] || usage

TARGET=$1
BACKUP_ROOT=$2

[ -n "$TARGET" ] || usage
[ -n "$BACKUP_ROOT" ] || usage

case "$TARGET" in
    -*)
        error "router target must not start with '-'"
        exit 2
        ;;
esac

require_local_command ssh
require_local_command tar
require_local_command grep
require_local_command date
require_local_command mkdir
require_local_command mv
require_local_command rm

if command -v sha256sum >/dev/null 2>&1; then
    CHECKSUM_TOOL=sha256sum
elif command -v shasum >/dev/null 2>&1; then
    CHECKSUM_TOOL=shasum
else
    error "required checksum tool not found: need sha256sum or shasum"
    exit 1
fi

checksum_create() {
    case "$CHECKSUM_TOOL" in
        sha256sum)
            sha256sum "$@"
            ;;
        shasum)
            shasum -a 256 "$@"
            ;;
    esac
}

checksum_verify() {
    case "$CHECKSUM_TOOL" in
        sha256sum)
            sha256sum -c SHA256SUMS
            ;;
        shasum)
            shasum -a 256 -c SHA256SUMS
            ;;
    esac
}

# Backup contents and the SSH control socket may contain or grant access to
# sensitive material. Keep all newly created files private to the invoking user.
umask 077

STAMP=$(date '+%Y-%m-%d_%H%M%S')
DEST="$BACKUP_ROOT/router-$STAMP"
WORK="$BACKUP_ROOT/.router-$STAMP.partial"
CONTROL_PATH="$BACKUP_ROOT/.openwrt-backup-ssh-$$.sock"
MASTER_STARTED=0

cleanup() {
    if [ "$MASTER_STARTED" -eq 1 ]; then
        ssh \
            -o BatchMode=yes \
            -o ControlPath="$CONTROL_PATH" \
            -O exit \
            -- \
            "$TARGET" >/dev/null 2>&1 || true
    fi

    rm -f "$CONTROL_PATH"
}

trap cleanup EXIT HUP INT TERM

mkdir -p "$BACKUP_ROOT"

if [ -e "$WORK" ] || [ -e "$DEST" ]; then
    error "snapshot path already exists:"
    echo "  $WORK" >&2
    echo "  $DEST" >&2
    exit 1
fi

if [ -e "$CONTROL_PATH" ]; then
    error "SSH control path already exists: $CONTROL_PATH"
    exit 1
fi

mkdir "$WORK"

printf '%s\n' "Opening SSH master connection to $TARGET ..."
if ! ssh \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o ConnectionAttempts=1 \
    -o ControlMaster=yes \
    -o ControlPath="$CONTROL_PATH" \
    -o ControlPersist=no \
    -Nf \
    -- \
    "$TARGET"
then
    error "could not establish SSH connection to $TARGET"
    echo "Partial data retained at: $WORK" >&2
    exit 1
fi
MASTER_STARTED=1

ssh_router() {
    ssh \
        -o BatchMode=yes \
        -o ControlMaster=no \
        -o ControlPath="$CONTROL_PATH" \
        -- \
        "$TARGET" "$@"
}

fail() {
    error "$1"
    echo "Partial data retained at: $WORK" >&2
    exit 1
}

printf '%s\n' "Checking remote OpenWrt prerequisites on $TARGET ..."
# shellcheck disable=SC2016
if ! ssh_router '
    for cmd in sysupgrade uci ubus ip; do
        command -v "$cmd" >/dev/null 2>&1 || {
            echo "Missing required remote command: $cmd" >&2
            exit 1
        }
    done
'; then
    fail "remote prerequisite check failed"
fi

printf '%s\n' "Creating OpenWrt configuration backup from $TARGET ..."
if ! ssh_router 'sysupgrade -k -b -' > "$WORK/openwrt-backup.tar.gz"; then
    fail "OpenWrt backup command failed"
fi

[ -s "$WORK/openwrt-backup.tar.gz" ] || fail "backup archive is empty"

printf '%s\n' "Validating backup archive ..."
if ! tar -tzf "$WORK/openwrt-backup.tar.gz" > "$WORK/archive-contents.txt"; then
    fail "backup archive is not a readable tar.gz"
fi

# Minimal recovery sanity checks. These do not define the complete OpenWrt
# backup contents; they catch an obviously unusable snapshot.
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
    checksum_create \
        openwrt-backup.tar.gz \
        archive-contents.txt \
        sysupgrade-file-list.txt \
        system-inventory.txt \
        uci-export.txt \
        router-target.txt \
        > SHA256SUMS

    checksum_verify
); then
    fail "checksum verification failed"
fi

# WORK and DEST are deliberately below the same parent, so this rename publishes
# the already validated snapshot without exposing a half-built final directory.
if ! mv "$WORK" "$DEST"; then
    fail "could not publish validated snapshot"
fi

printf '\nSnapshot completed successfully:\n%s\n' "$DEST"
