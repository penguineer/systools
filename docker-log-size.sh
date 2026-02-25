#!/bin/bash
# List the sizes of the JSON log files for all available containers.
#
# Configuration via environment:
#	DOCKER_BASE_PATH	base path for docker data (default: /var/lib/docker)
#
# Note: You need to have permissions to access the docker data directory (e.g. by running this script with sudo)
# to get the log file sizes. The output is sent to stdout and can be used in a pipeline.
#
# Author: Stefan Haun <tux@netz39.de>
#
# SPDX-License-Identifier: MIT
# License-Filename: LICENSES/MIT.txt

set -euo pipefail

DOCKER_BASE_PATH="${DOCKER_BASE_PATH:-/var/lib/docker}"
CONTAINERS_DIR="${DOCKER_BASE_PATH%/}/containers"

tmp="${TMPDIR:-/tmp}/docker-json-log-sizes.$$"

sudo docker ps -aq | while IFS= read -r cid; do
  # Expand to the full 64-char ID so we can locate the on-disk log file
  full_id="$(sudo docker inspect -f '{{.Id}}' "$cid" 2>/dev/null || true)"
  [[ -n "${full_id:-}" ]] || continue

  log="${CONTAINERS_DIR}/${full_id}/${full_id}-json.log"
  [[ -f "$log" ]] || continue

  size="$(sudo stat -c '%s' "$log" 2>/dev/null || echo 0)"
  name="$(sudo docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's#^/##' || true)"
  [[ -n "${name:-}" ]] || name="unknown"

  # Output: bytes, short id, name (stable + easy to read)
  printf "%s\t%s\t%s\n" "$size" "$cid" "$name"
done > "$tmp.raw"

# Stable order (by name, then container id)
sort -t $'\t' -k3,3 -k2,2 "$tmp.raw" > "$tmp.sorted"

# Total over the same set
awk -F'\t' '{s+=$1} END{printf "total_bytes=%d total_gib=%.2f\n", s, s/1024/1024/1024}' \
  "$tmp.sorted"

# Full list
awk -F'\t' 'BEGIN{print "bytes\tcontainer_id\tname"} {printf "%s\t%s\t%s\n",$1,$2,$3}' \
  "$tmp.sorted"

rm -f "$tmp.raw" "$tmp.sorted"
