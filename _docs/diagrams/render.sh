#!/usr/bin/env bash
# Render each D2 source to a light + dark SVG pair for the docs site.
#
# MkDocs Material switches images by appending #only-light / #only-dark to the
# src and toggling visibility per color scheme — so each diagram needs two
# static files, NOT one prefers-color-scheme-responsive file (Material's toggle
# doesn't drive the OS media query).
#
# Each source carries its gruvbox palette in `vars.d2-config`:
#   theme-overrides       -> gruvbox light   (rendered on base theme 0)
#   dark-theme-overrides  -> gruvbox dark    (promoted onto base theme 200)
#
# Output:  <name>-light.svg  and  <name>-dark.svg  next to this script.
# Embed:   ![alt](../diagrams/<name>-light.svg#only-light)
#          ![alt](../diagrams/<name>-dark.svg#only-dark)
#
# Requires: d2 (`brew install d2`) and python3.
# Usage:    ./render.sh            # all sources
#           ./render.sh foo.d2     # one source
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
shopt -s nullglob

render() {
  local src="$1"
  local base="$(basename "${src%.d2}")"

  # Light: theme-overrides applies to base theme 0 directly.
  d2 --sketch --theme 0 --pad 30 "$src" "${here}/${base}-light.svg"

  # Dark: promote dark-theme-overrides into theme-overrides, render on theme 200.
  local tmp
  tmp="$(mktemp --suffix=.d2)"
  python3 - "$src" "$tmp" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
# Promote the dark palette into theme-overrides; render that on dark base theme 200.
dark = re.search(r'dark-theme-overrides:\s*\{(.*?)\n    \}', src, re.S).group(1)
light = re.search(r'theme-overrides:\s*\{.*?\n    \}', src, re.S).group(0)  # first match = light
out = src.replace(light, 'theme-overrides: {' + dark + '\n    }')
# Drop the now-duplicate dark block (matched from its comment label).
out = re.sub(r'\n\s*# Gruvbox Material — dark.*?dark-theme-overrides:\s*\{.*?\n    \}', '', out, flags=re.S)
open(sys.argv[2], 'w').write(out)
PY
  d2 --sketch --theme 200 --pad 30 "$tmp" "${here}/${base}-dark.svg"
  rm -f "$tmp"
  echo "rendered: ${base}-{light,dark}.svg"
}

if [[ $# -gt 0 ]]; then
  render "${here}/src/$1"
else
  for f in "${here}/src/"*.d2; do
    render "$f"
  done
fi
