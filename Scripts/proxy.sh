#!/bin/bash
# Serves the assistant proxy on http://localhost:8787, the address Debug builds call. Extra arguments pass to `wrangler dev`.
set -euo pipefail
cd "$(dirname "$0")/../Server/larder-proxy"
if [ ! -f .dev.vars ]; then
    echo "error: Server/larder-proxy/.dev.vars is missing; copy .dev.vars.example to it and fill in the values" >&2
    exit 1
fi
if [ ! -d node_modules ]; then
    npm ci
fi
exec npx wrangler dev --port 8787 "$@"
