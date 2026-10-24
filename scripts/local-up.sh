#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .real
export PORT="${PORT:-8820}"
lsof -ti "tcp:$PORT" | xargs kill -9 2>/dev/null || true
sleep 1
nohup mix run --no-halt > ".real/server-$PORT.log" 2>&1 &
for _ in $(seq 1 60); do
  sleep 1
  curl -s -m 2 "localhost:$PORT/summary" | grep -q total && { echo "swarm up on :$PORT"; exit 0; }
done
echo "swarm did not start; see .real/server-$PORT.log" >&2
exit 1
