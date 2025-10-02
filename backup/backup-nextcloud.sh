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

DEFAULT_NC_INSTANCE=nextcloud
DEFAULT_NC_USER=www-data
DEFAULT_NC_BASE=/var/www/html
DEFAULT_NC_DSTPATH=$(pwd)

DOCKER=/usr/bin/docker
SQLITE=/usr/bin/sqlite3
TAR=/bin/tar
BZIP2=/bin/bzip2
DIRS=( "config" "data" "themes" "apps")

## Check parameters
if [ -z "$NC_INSTANCE" ]; then
	NC_INSTANCE=$DEFAULT_NC_INSTANCE
	echo "Using default instance $NC_INSTANCE."
else
	echo "Using override instance $NC_INSTANCE."
fi

if [ -z "$NC_USER" ]; then
	NC_USER=$DEFAULT_NC_USER
	echo "Using default user $NC_USER."
else
	echo "Using override user $NC_USER."
fi

if [ -z "$NC_BASE" ]; then
	NC_BASE=$DEFAULT_NC_BASE
	echo "Using default base path $NC_BASE."
else
	echo "Using override base path $NC_BASE."
fi

if [ -z "$NC_DSTPATH" ]; then
	NC_DSTPATH=$DEFAULT_NC_DSTPATH
	echo "Using default destination path $NC_DSTPATH (current wirking directory)."
else
	echo "Using override destination path $NC_DSTPATH."
fi


# https://stackoverflow.com/questions/2990414/echo-that-outputs-to-stderr
function echoerr() {
	printf "%s\n" "$*" >&2;
}

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
if [ -n "$TMP_PREFIX" ]; then
  mkdir -p "$TMP_PREFIX"
  TMPDIR=$(mktemp -d -p "$TMP_PREFIX" -t "nextcloud.XXXXXX")
else
  TMPDIR=$(mktemp -d -t "nextcloud.XXXXXX")
fi

if [[ ! "$TMPDIR" || ! -d "$TMPDIR" ]]; then
	echoerr "Could not create temporary directory!"
	exit 1
fi;

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

if [ -z "$NC_DSTPATH" ]; then
	echoerr "Destination path has not been provided in NC_DSTPATH!"
	exit 1
fi

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
