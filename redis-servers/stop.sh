#!/usr/bin/env bash
set -euo pipefail

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$base_dir/stop-sentinel.sh"
"$base_dir/stop-redis-6381.sh"
"$base_dir/stop-redis-6380.sh"
