#!/bin/bash
# Runs the UI tests (accessibility audits and screenshots); extra arguments pass to xcodebuild,
# e.g. -only-testing:LarderUITests/LarderUITests/testDynamicTypeAX3.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/env.sh
simulator="$(Scripts/simulator.sh)"
echo "Testing Larder on ${simulator}"
xcodebuild -project Larder.xcodeproj -scheme Larder -destination "platform=iOS Simulator,name=${simulator}" \
    test CODE_SIGNING_ALLOWED=NO "$@" 2>&1 \
    | grep --line-buffered -E "Test Case .*(passed|failed)|error:|Executed|\*\* TEST"
