#!/usr/bin/env bash
set -euo pipefail

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$base_dir/start-redis-6380.sh"
"$base_dir/start-redis-6381.sh"
"$base_dir/start-sentinel.sh"
