#!/usr/bin/env bash
set -euo pipefail

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$base_dir/redis-servers/node.sh" start "Redis node 6380" 6380 node-6380/redis.conf
