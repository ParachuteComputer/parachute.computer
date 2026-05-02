#!/usr/bin/env bash
# scripts/optimize-pitch-images.sh
#
# One-off image optimization for /pitch. Produces compressed PNG + WebP at
# 800w / 1600w / 2400w into assets/pitch/optimized/. Originals stay in
# assets/pitch/ for reuse later.
#
# Run:  bash scripts/optimize-pitch-images.sh
#
# Requires: npx (uses sharp-cli transiently — no devDep added).
set -euo pipefail

SRC=assets/pitch
OUT=assets/pitch/optimized
mkdir -p "$OUT"

process() {
  local name=$1
  local widths=$2
  local input="$SRC/$name.png"
  echo "→ $name  (widths: $widths)"
  for w in $widths; do
    npx --yes sharp-cli -i "$input" -o "$OUT/${name}-${w}w.webp" -f webp -q 82 resize "$w" >/dev/null
  done
}

# Hero gets 2400w; smaller images max out at 1600w.
process hero-pendant-walking  "800 1600 2400"
process agent-race-landscape  "800 1600"
process vault-architecture    "800 1600 2400"
process pendant-pcb           "800 1600"
process pendant-render        "800 1600"
process pendant-worn          "800 1600"

echo
echo "Done. Output:"
ls -lh "$OUT" | awk 'NR>1 {printf "  %-8s  %s\n", $5, $NF}'
