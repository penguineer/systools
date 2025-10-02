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

DOCKER=/usr/bin/docker
SQLITE=/usr/bin/sqlite3
TAR=/bin/tar
BZIP2=/bin/bzip2
DIRS=( "config" "data" "themes" "apps")

## Check arguments
DEFAULT_NC_INSTANCE=nextcloud
DEFAULT_NC_USER=www-data
DEFAULT_NC_BASE=/var/www/html
DEFAULT_NC_DSTPATH=$(pwd)

set_default_argument NC_INSTANCE "$DEFAULT_NC_INSTANCE" "instance"
set_default_argument NC_USER "$DEFAULT_NC_USER" "user"
set_default_argument NC_BASE "$DEFAULT_NC_BASE" "base path"
set_default_argument NC_DSTPATH "$DEFAULT_NC_DSTPATH" "destination path"


function maintenance_mode() {
	local MODE=$1
	
	if [ -z "$MODE" ]; then
		echoerr "Maintenance mode has not been specified!"
		return 1
	fi
	
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

# Make sure we remove the tmp directory on exit and errors
trap 'rm -rf "$TMPDIR"' EXIT

pushd "$TMPDIR" || exit

## Activate Maintenance Mode
maintenance_mode on
if [ "$?" != "0" ]; then
	exit $?
fi

## Copy backup data

for d in "${DIRS[@]}"
do
	echo "Copying from $NC_INSTANCE:$NC_BASE/$d to $TMPDIR …"
	$DOCKER cp -a "$NC_INSTANCE:$NC_BASE/$d" "$TMPDIR"
	if [ "$?" != "0" ]; then
		exit $?
	fi
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
$BZIP2 "$TMPDIR/db.dump"

## Pack File Data
echo "Packing file data …"
for d in "${DIRS[@]}"
do
	tar cjf "$TMPDIR/$d.tar.bz2" "$d"
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

## Cleanup
popd || exit

# $TMPDIR will be removed by the trap

echo "Done."
