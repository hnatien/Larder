#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# The scheme's Run environment carries the proxy's dev attestation secret for Simulator runs. Take it from the
# environment, else from the local Worker's .dev.vars; either way it lands only in the git-ignored project.
dev_vars="Server/larder-proxy/.dev.vars"
if [ -z "${LARDER_DEV_CLIENT_SECRET:-}" ] && [ -f "$dev_vars" ]; then
    secret="$(sed -n 's/^DEV_CLIENT_SECRET=//p' "$dev_vars" | tail -1)"
    secret="${secret%\"}"
    secret="${secret#\"}"
    LARDER_DEV_CLIENT_SECRET="$secret"
fi
if [ -z "${LARDER_DEV_CLIENT_SECRET:-}" ]; then
    echo "warning: no DEV_CLIENT_SECRET in $dev_vars; Simulator runs cannot reach the assistant proxy" >&2
fi
export LARDER_DEV_CLIENT_SECRET="${LARDER_DEV_CLIENT_SECRET:-}"

xcodegen generate
