#!/bin/bash
set -Eeuo pipefail

# Notify admin about backup failure via email
# Requires the following environment variables to be set:
#   EMAIL - email address to send the notification to
#   SERVICE - name of the service to check (without .service)
#   EVENT - optional, event description (default: "Service execution")

# Abort interrupted
trap 'exit 130' INT

# Include utils
. "$(dirname "$0")/backup-utils.sh"

assert_env EMAIL
assert_env SERVICE
set_default_argument EVENT "Service execution" "event"

require_command MAIL mail

# Get the timestamp of the last "Started" event
START_TS=$(journalctl -u "$SERVICE.service" --output=short-unix | grep "Starting $SERVICE.service" | tail -1 | awk '{print $1}')

if [[ -z "$START_TS" ]]; then
  LOG="
Error: No 'Starting' log entry found for $SERVICE.service. Cannot determine start time.

$( journalctl -u "$SERVICE.service" -n 20 --no-pager )
"
else
  # Get the log entries since the last service start
  LOG=$( journalctl -u "$SERVICE.service" --since="@$START_TS" --no-pager )
fi

SUBJECT="$EVENT for $SERVICE on $(hostname) at $(date +'%Y-%m-%d %H:%M:%S')"

BODY="$SUBJECT

The following has been logged +++
$LOG
+++"

echo -e "$BODY" | $MAIL -s "$SUBJECT" "$EMAIL"
