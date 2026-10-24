#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
COUNT="${COUNT:-200}"
export COUNT
mix run --no-start scripts/gate.exs
