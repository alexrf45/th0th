#!/usr/bin/env bash
# Acceptance test for O-11 — Gatus endpoint status badges in repo README.
#
# Asserts:
#   - README.md exists
#   - 6 Gatus badge URLs are embedded (one per endpoint key)
#   - Stale Syncthing row is gone (spun down 2026-05-15)
#   - All 6 endpoint identifiers are still surfaced in README copy
#   - Optional: markdownlint clean if installed
#
# Pure static; no cluster calls, no push.

set -euo pipefail

TASK_ID="O-11"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

say() { printf '\033[1;34m[accept:%s]\033[0m %s\n' "$TASK_ID" "$*"; }
fail() { printf '\033[1;31m[accept:%s FAIL]\033[0m %s\n' "$TASK_ID" "$*" >&2; exit 1; }

# 1. README.md exists.
[[ -f README.md ]] || fail "README.md missing at repo root"
say "README.md present"

# 2. Six Gatus badge URLs — one per endpoint key (group_name).
#    The canonical keys come from the live API:
#      curl -s https://dev-status.home-0ps.com/api/v1/endpoints/statuses \
#        | jq -r '.[].key'
ENDPOINT_KEYS=(
  applications_authentik
  applications_grafana
  applications_freshrss
  applications_homer
  infrastructure_truenas
  infrastructure_unifi
)
for key in "${ENDPOINT_KEYS[@]}"; do
  if ! grep -qF "dev-status.home-0ps.com/api/v1/endpoints/${key}/" README.md; then
    fail "missing Gatus badge URL for endpoint key: ${key}"
  fi
done
say "all 6 Gatus endpoint badge URLs present"

# 3. Sanity: total references to the Gatus public hostname should be >= 6.
DEV_STATUS_HITS=$(grep -c "dev-status.home-0ps.com" README.md || true)
if (( DEV_STATUS_HITS < 6 )); then
  fail "expected >= 6 references to dev-status.home-0ps.com in README.md, got ${DEV_STATUS_HITS}"
fi
say "dev-status.home-0ps.com references: ${DEV_STATUS_HITS}"

# 4. Stale Syncthing row removed (spun down 2026-05-15).
if grep -qi 'syncthing' README.md; then
  fail "stale 'Syncthing' reference still in README.md (spun down 2026-05-15)"
fi
say "Syncthing reference removed"

# 5. Sanity — all six endpoint names still surfaced (case-insensitive).
for token in authentik grafana freshrss homer truenas unifi; do
  if ! grep -qi "${token}" README.md; then
    fail "missing endpoint token in README copy: ${token}"
  fi
done
say "all 6 endpoint tokens surfaced in README copy"

# 6. Optional markdownlint.
if command -v markdownlint >/dev/null 2>&1; then
  say "markdownlint README.md"
  markdownlint README.md || fail "markdownlint failed"
else
  say "markdownlint not installed — skipping"
fi

say "PASS"
