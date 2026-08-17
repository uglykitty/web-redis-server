#!/usr/bin/env bash
set -euo pipefail

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pid_file="$base_dir/webdis.pid"

if [[ ! -f "$pid_file" ]] || ! kill -0 "$(<"$pid_file")" 2>/dev/null; then
  rm -f "$pid_file"
  echo "Webdis is not running"
  exit 0
fi

pid="$(<"$pid_file")"
kill "$pid"

for _ in {1..50}; do
  if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$pid_file"
    echo "Webdis stopped"
    exit 0
  fi
  sleep 0.1
done

echo "Webdis did not stop within 5 seconds" >&2
exit 1
