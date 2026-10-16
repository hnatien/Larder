#!/bin/bash
# Writes light and dark screenshots of every tab to docs/screenshots.
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/test-app.sh -only-testing:LarderUITests/LarderUITests/testScreenshots
ls docs/screenshots/*.png
