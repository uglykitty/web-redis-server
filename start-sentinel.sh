#!/usr/bin/env bash
set -euo pipefail

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$base_dir/redis-servers/node.sh" start "Redis Sentinel" 26379 sentinel/sentinel.conf --sentinel
