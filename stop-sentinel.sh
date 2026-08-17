#!/usr/bin/env bash
set -euo pipefail

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$base_dir/redis-servers/node.sh" stop "Redis Sentinel" 26379
