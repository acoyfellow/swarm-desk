#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tag="${1:?image tag, e.g. v1}"
config="${WRANGLER_CONFIG:-cloud/wrangler.jsonc}"
docker build --platform linux/amd64 -t "swarm-desk:$tag" .
cd cloud
npx wrangler containers push "swarm-desk:$tag" -c "../$config"
sed -i.bak -E "s#swarm-desk:v[0-9]+#swarm-desk:$tag#" "../$config" && rm -f "../$config.bak"
npx wrangler deploy -c "../$config"
