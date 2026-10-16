#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/env.sh
simulator="$(Scripts/simulator.sh)"
echo "Building Larder for ${simulator}"
xcodebuild -project Larder.xcodeproj -scheme Larder -destination "platform=iOS Simulator,name=${simulator}" \
    build CODE_SIGNING_ALLOWED=NO | tail -30
