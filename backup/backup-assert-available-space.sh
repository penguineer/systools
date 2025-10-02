#!/bin/bash
set -Eeuo pipefail

# Check for available space and exit with error if not enough space is available.
#
# This script uses environment variables to be compatible with systemd.
#   BACKUP_DSTPATH        destination path for the backup (default: pwd)
#   BACKUP_SIZE_MIN_MIB   minimum required space in MiB (default: 1024)
#
# Author: Stefan Haun <tux@netz39.de>
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSES/MIT.txt

# Include utils
. "$(dirname "$0")/backup-utils.sh"

DEFAULT_BACKUP_DSTPATH=$(pwd)
DEFAULT_BACKUP_SIZE_MIN_MiB=1024

echo "Checking available space …"

set_default_argument BACKUP_DSTPATH "$DEFAULT_BACKUP_DSTPATH" "destination path"
set_default_argument BACKUP_SIZE_MIN_MIB "$DEFAULT_BACKUP_SIZE_MIN_MiB" "minimum size"

# Calculate required and available space in KiB

REQUIRED_SPACE_KIB=$((BACKUP_SIZE_MIN_MIB * 1024))
AVAILABLE_SPACE_KIB=$(df --output=avail -k "$BACKUP_DSTPATH" 2>/dev/null | tail -n +2 | tr -d '[:space:]')

if (( AVAILABLE_SPACE_KIB < REQUIRED_SPACE_KIB )); then
  echo "Not enough space for backup! Required: ${BACKUP_SIZE_MIN_MIB} MiB, Available: $((AVAILABLE_SPACE_KIB / 1024)) MiB" >&2
  exit 1
fi

echo "Sufficient space available: $((AVAILABLE_SPACE_KIB / 1024)) MiB"
