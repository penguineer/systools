#! /bin/bash
#
# Backup for a TwentyCRM instance running inside a docker container.
#
# Configuration via environment:
#	TW_DB_INSTANCE	name of the Twenty DB docker container (default: twenty-db-1)
# TW_POSTGRES_USER name of the postgres user (default: postgres)
#	TW_DSTPATH	destination base path for the backup (default: pwd)
#
# For the process see
# https://twenty.com/developers/section/self-hosting/upgrade-guide
#
# Author: Stefan Haun <tux@netz39.de>
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSES/MIT.txt

DEFAULT_TW_DB_INSTANCE=twenty-db-1
DEFAULT_TW_POSTGRES_USER=postgres
DEFAULT_TW_DSTPATH=$(pwd)

DOCKER=/usr/bin/docker
BZIP2=/bin/bzip2

## Check parameters
if [ -z "${TW_DB_INSTANCE:-}" ]; then
	TW_DB_INSTANCE=$DEFAULT_TW_DB_INSTANCE
	echo "Using default instance $TW_DB_INSTANCE."
else
	echo "Using override instance $TW_DB_INSTANCE."
fi

if [ -z "${TW_POSTGRES_USER:-}" ]; then
  TW_POSTGRES_USER=$DEFAULT_TW_POSTGRES_USER
  echo "Using default postgres user $TW_POSTGRES_USER."
else
  echo "Using override postgres user $TW_POSTGRES_USER."
fi

if [ -z "${TW_DSTPATH:-}" ]; then
	TW_DSTPATH=$DEFAULT_TW_DSTPATH
	echo "Using default destination path $TW_DSTPATH (current working directory)."
else
	echo "Using override destination path $TW_DSTPATH."
fi


# https://stackoverflow.com/questions/2990414/echo-that-outputs-to-stderr
function echoerr() {
	printf "%s\n" "$*" >&2;
}

## Create tmp dir
TMPDIR=$(mktemp -d)

if [[ ! "$TMPDIR" || ! -d "$TMPDIR" ]]; then
	echoerr "Could not create temporary directory!"
	exit 1
fi;

pushd "$TMPDIR" || exit

## Dump Database
echo "Dumping database …"
$DOCKER exec -it $DEFAULT_TW_DB_INSTANCE pg_dumpall -U "$TW_POSTGRES_USER" > "$TMPDIR/tw_database.sql"
$BZIP2 "$TMPDIR/tw_database.sql"

## Copy to backup location
echo "Copy to backup location …"

if [ -z "$TW_DSTPATH" ]; then
	echoerr "Destination path has not been provided in TW_DSTPATH!"
	exit 1
fi

mkdir -p "$TW_DSTPATH"
if [ ! -d "$TW_DSTPATH" ]; then
	echoerr "Destination path does not exist and could not be created!"
	exit 1
fi

mv "$TMPDIR/tw_database.sql.bz2" "$TW_DSTPATH"

## Cleanup
echo "Cleanup …"

popd || exit

if [ -d "$TMPDIR" ]; then
	rm -rf "$TMPDIR"
fi

echo "Done."
