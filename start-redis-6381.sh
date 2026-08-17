#!/usr/bin/env bash
set -euo pipefail

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$base_dir/redis-servers/node.sh" start "Redis node 6381" 6381 node-6381/redis.conf
