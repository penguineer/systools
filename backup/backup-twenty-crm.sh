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
# Abort and clean up when interrupted
trap 'exit 130' INT

# Include utils
. "$(dirname "$0")/backup-utils.sh"

require_command DOCKER docker
require_command BZIP2 bzip2

## Check arguments
DEFAULT_TW_DB_INSTANCE=twenty-db-1
DEFAULT_TW_POSTGRES_USER=postgres
DEFAULT_TW_DSTPATH=$(pwd)

set_default_argument TW_DB_INSTANCE "$DEFAULT_TW_DB_INSTANCE" "instance"
set_default_argument TW_POSTGRES_USER "$DEFAULT_TW_POSTGRES_USER" "postgres user"
set_default_argument TW_DSTPATH "$DEFAULT_TW_DSTPATH" "destination path"


# Create tmp dir
TMPDIR=$(create_tmpdir "twenty" "$TMP_PREFIX")
echo "Using temporary directory $TMPDIR"

cleanup() {
  safe_popd
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

pushd "$TMPDIR" || exit

## Dump Database
echo "Dumping database …"
$DOCKER exec $DEFAULT_TW_DB_INSTANCE pg_dumpall -U "$TW_POSTGRES_USER" > "$TMPDIR/tw_database.sql"
propagate_error_condition

echo "Compressing database dump …"
$BZIP2 "$TMPDIR/tw_database.sql"
propagate_error_condition

## Copy to backup location
echo "Copy to backup location …"

mkdir -p "$TW_DSTPATH"
if [ ! -d "$TW_DSTPATH" ]; then
	echoerr "Destination path does not exist and could not be created!"
	exit 1
fi

mv "$TMPDIR/tw_database.sql.bz2" "$TW_DSTPATH"

echo "Done."
## Cleanup is done by the trap

