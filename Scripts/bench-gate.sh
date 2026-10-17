#!/bin/bash
# LarderBench regression gate for planner changes (docs/EVALUATION.md, "Regression gate"): exits 1 when the planner
# regresses against Scripts/bench-baseline.json. Pass --update to rewrite the baseline after an intended change.
set -euo pipefail
cd "$(dirname "$0")/.."
source Scripts/env.sh
config=(--seed 42 --seeds 3 --households 40 --weeks 4)
baseline=Scripts/bench-baseline.json
if [ "${1:-}" = "--update" ]; then
    swift run -c release LarderBench "${config[@]}" --write-baseline "$baseline"
else
    swift run -c release LarderBench "${config[@]}" --check-baseline "$baseline"
fi
