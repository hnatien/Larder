#!/bin/bash
# Prints the simulator to build and test on: $LARDER_SIMULATOR when set, otherwise an "iPhone NN Pro"
# (a standard compact-width phone) from the newest runtime that has one, otherwise the newest runtime's first iPhone.
set -euo pipefail
source "$(dirname "$0")/env.sh"
if [ -n "${LARDER_SIMULATOR:-}" ]; then
    echo "${LARDER_SIMULATOR}"
    exit 0
fi
xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    return [int(part) for part in re.findall(r"\d+", runtime.rsplit(".", 1)[-1])]
runtimes = sorted((r for r in devices if ".iOS-" in r), key=version, reverse=True)
phones = [device["name"] for runtime in runtimes for device in devices[runtime] if device["name"].startswith("iPhone")]
pro = [name for name in phones if re.fullmatch(r"iPhone \d+ Pro", name)]
if pro or phones:
    print((pro or phones)[0])
    sys.exit(0)
sys.exit("No available iPhone simulator. Install one in Xcode > Settings > Components.")
'
