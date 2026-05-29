#!/usr/bin/env bash
# Render all D2 diagram sources to responsive (light/dark) SVGs.
#
# Each source in src/*.d2 carries its own gruvbox-material palette via a
# `vars.d2-config.theme-overrides` (light) + `dark-theme-overrides` (dark)
# block, so the emitted SVG switches automatically with prefers-color-scheme
# — which MkDocs Material's light/dark toggle drives.
#
# Usage:  ./render.sh           # render every src/*.d2
#         ./render.sh foo.d2    # render a single source
#
# Requires: d2 (https://d2lang.com). Install: `brew install d2`.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
shopt -s nullglob

render() {
  local src="$1"
  local out="${here}/$(basename "${src%.d2}").svg"
  d2 --sketch --theme 0 --dark-theme 200 --pad 30 "$src" "$out"
  echo "rendered: $out"
}

if [[ $# -gt 0 ]]; then
  render "${here}/src/$1"
else
  for f in "${here}/src/"*.d2; do
    render "$f"
  done
fi
