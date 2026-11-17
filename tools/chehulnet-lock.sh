#!/usr/bin/env bash
# Fails when a vendored copy of the ChehulNet library differs from what chehulnet.lock recorded. The copies ship
# identical in every Chehul addon and change only through danielcosta42/chehulnet's tools/sync.sh, never by hand:
# a fix made in one addon's copy would be lost at the next sync and would never reach the others.
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
while read -r kind path want; do
  [ "$kind" = "file" ] || continue
  got=$(git hash-object --path="$path" "$path")
  if [ "$got" != "$want" ]; then
    echo "$path differs from chehulnet.lock: change it in danielcosta42/chehulnet and run its tools/sync.sh" >&2
    status=1
  fi
done < chehulnet.lock
if [ "$status" -eq 0 ]; then echo "chehulnet $(sed -n 's/^tag //p' chehulnet.lock): copies intact"; fi
exit "$status"
