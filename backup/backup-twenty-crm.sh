#! /bin/bash

# Backup for a TwentyCRM instance running inside a docker container.
#
# Configuration via environment:
#	TW_DB_INSTANCE	name of the Twenty DB docker container (default: twenty-db-1)
# TW_POSTGRES_USER name of the postgres user (default: postgres)
#	TW_DSTPATH	destination base path for the backup (default: pwd)
# TMP_PREFIX  prefix for the temporary directory (default: auto, see mktemp)
#
# For the process see
# https://twenty.com/developers/section/self-hosting/upgrade-guide
#
# Note: This script is intended to be run from a cron job and therefore does not
# have access to a terminal. All output is sent to stdout/stderr.
#
# Author: Stefan Haun <tux@netz39.de>
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSES/MIT.txt

set -Eeuo pipefail

# Include utils
. "$(dirname "$0")/backup-utils.sh"

DOCKER="$(command -v docker)"
BZIP2="$(command -v bzip2)"

if [ -z "$DOCKER" ]; then
  echo "Error: docker not found in PATH." >&2
  exit 1
fi
if [ -z "$BZIP2" ]; then
  echo "Error: bzip2 not found in PATH." >&2
  exit 1
fi

## Check arguments
DEFAULT_TW_DB_INSTANCE=twenty-db-1
DEFAULT_TW_POSTGRES_USER=postgres
DEFAULT_TW_DSTPATH=$(pwd)

set_default_argument TW_DB_INSTANCE "$DEFAULT_TW_DB_INSTANCE" "instance"
set_default_argument TW_POSTGRES_USER "$DEFAULT_TW_POSTGRES_USER" "postgres user"
set_default_argument TW_DSTPATH "$DEFAULT_TW_DSTPATH" "destination path"


# Create tmp dir
if [ -n "$TMP_PREFIX" ]; then
  mkdir -p "$TMP_PREFIX"
  TMPDIR=$(mktemp -d -p "$TMP_PREFIX" -t "twentycrm.XXXXXX")
else
  TMPDIR=$(mktemp -d -t "twentycrm.XXXXXX")
fi

if [[ ! "$TMPDIR" || ! -d "$TMPDIR" ]]; then
	echoerr "Could not create temporary directory!"
	exit 1
fi;

# Make sure we remove the tmp directory on exit and errors
trap 'rm -rf "$TMPDIR"' EXIT

pushd "$TMPDIR" || exit

## Dump Database
echo "Dumping database …"
$DOCKER exec $DEFAULT_TW_DB_INSTANCE pg_dumpall -U "$TW_POSTGRES_USER" > "$TMPDIR/tw_database.sql"
$BZIP2 "$TMPDIR/tw_database.sql"

## Copy to backup location
echo "Copy to backup location …"

mkdir -p "$TW_DSTPATH"
if [ ! -d "$TW_DSTPATH" ]; then
	echoerr "Destination path does not exist and could not be created!"
	exit 1
fi

mv "$TMPDIR/tw_database.sql.bz2" "$TW_DSTPATH"

## Cleanup
popd || exit

# $TMPDIR will be removed by the trap

echo "Done."
