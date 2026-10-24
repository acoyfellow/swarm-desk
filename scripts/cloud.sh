#!/usr/bin/env bash
set -euo pipefail
: "${SWARM_URL:?set SWARM_URL to your deployed Worker, e.g. https://swarm.example.com}"
path="${1:-/summary}"
method="${2:-GET}"
body="${3:-}"
auth=()
[ -n "${ACCESS_TOKEN:-}" ] && auth=(-H "cf-access-token: $ACCESS_TOKEN")
if [ -n "$body" ]; then
  curl -s -m 60 -X "$method" "${auth[@]}" -H "content-type: application/json" --data "$body" "$SWARM_URL$path"
else
  curl -s -m 60 -X "$method" "${auth[@]}" "$SWARM_URL$path"
fi
