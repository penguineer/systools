#! /bin/bash
#
# Backup for a NextCloud instance running inside a docker container.
#
# Configuration via environment:
#	NC_INSTANCE	name of the docker container (default: nextcloud)
#	NC_USER		name of the nextcloud system user (default: www-data)
#	NC_BASE		base directory for nextcloud files (default: /var/www/html)
#	NC_DSTPATH	destination base path for the backup (default: pwd)
# TMP_PREFIX  prefix for the temporary directory (default: auto, see mktemp)
#
# For the process see
# https://docs.nextcloud.com/server/13/admin_manual/maintenance/backup.html
#
# Author: Stefan Haun <tux@netz39.de>
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSES/MIT.txt

# Include utils
. "$(dirname "$0")/backup-utils.sh"

require_command DOCKER docker
require_command SQLITE sqlite3
require_command TAR tar
require_command BZIP2 bzip2

## Check arguments
DEFAULT_NC_INSTANCE=nextcloud
DEFAULT_NC_USER=www-data
DEFAULT_NC_BASE=/var/www/html
DEFAULT_NC_DSTPATH=$(pwd)

set_default_argument NC_INSTANCE "$DEFAULT_NC_INSTANCE" "instance"
set_default_argument NC_USER "$DEFAULT_NC_USER" "user"
set_default_argument NC_BASE "$DEFAULT_NC_BASE" "base path"
set_default_argument NC_DSTPATH "$DEFAULT_NC_DSTPATH" "destination path"

DIRS=( "config" "data" "themes" "apps")

# Function to enable/disable maintenance mode
# Usage: maintenance_mode MODE
#   MODE is either "on" or "off"
#   Returns 0 on success, 1 on failure
LAST_MAINTENANCE_MODE=""
function maintenance_mode() {
	local MODE=$1
	
	if [ -z "$MODE" ]; then
		echoerr "Maintenance mode has not been specified!"
		return 1
	fi

	LAST_MAINTENANCE_MODE="$MODE"
	
	if [ "$MODE" == "on" ] || [ "$MODE" == "off" ]; then
		#maintenance mode
		$DOCKER exec --user $NC_USER $NC_INSTANCE php occ maintenance:mode --$MODE
	else
		echoerr "Unknown mode: $MODE"
		return 1
	fi
	
	return $?
}

# Create tmp dir
TMPDIR=$(create_tmpdir "nextcloud" "$TMP_PREFIX")
echo "Using temporary directory $TMPDIR"

cleanup() {
  if [ "$LAST_MAINTENANCE_MODE" == "on" ]; then
    echo "Deactivating maintenance mode …"
    maintenance_mode off
  fi
  safe_popd
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

pushd "$TMPDIR" || exit

## Activate Maintenance Mode
maintenance_mode on
propagate_error_condition

## Copy backup data

for d in "${DIRS[@]}"
do
	echo "Copying from $NC_INSTANCE:$NC_BASE/$d to $TMPDIR …"
	$DOCKER cp -a "$NC_INSTANCE:$NC_BASE/$d" "$TMPDIR"
	propagate_error_condition
done

## Deactivate Maintenance Mode
maintenance_mode off
if [ "$?" != "0" ]; then
	echoerr "Could not deactivate the maintenance mode!"
	# keep going
fi

## Export Database
echo "Exporting database …"

$SQLITE "$TMPDIR/data/owncloud.db" .dump > "$TMPDIR/db.dump"
propagate_error_condition

$BZIP2 "$TMPDIR/db.dump"
propagate_error_condition

## Pack File Data
echo "Packing file data …"
for d in "${DIRS[@]}"
do
	$TAR cjf "$TMPDIR/$d.tar.bz2" "$d"
	propagate_error_condition
done

## Copy to backup location
echo "Copy to backup location …"

mkdir -p "$NC_DSTPATH"
if [ ! -d "$NC_DSTPATH" ]; then
	echoerr "Destination path does not exist and could not be created!"
	exit 1
fi

for d in "${DIRS[@]}"
do
	mv "$TMPDIR/$d.tar.bz2" "$NC_DSTPATH"
done

mv "$TMPDIR/db.dump.bz2" "$NC_DSTPATH"

echo "Done."
## Cleanup is done by the trap
