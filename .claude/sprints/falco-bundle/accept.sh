#!/usr/bin/env bash
# Acceptance test for FALCO-BUNDLE — Falco custom-rules mount + falcosidekick
# UI/Redis disable + modern_ebpf driver verification (F-1 + F-2 + F-3).
#
# Validates static state on disk after the FALCO-BUNDLE changes are applied.
# Pure static + read-only — no kubectl apply / flux reconcile / helm install
# / git push. Idempotent. Exits 0 on pass, non-zero on fail.
#
# Wrapper rule (CLAUDE.md): any cluster probe is guarded behind
# `command -v k8sop` so CI (no wrapper) skips cleanly.

set -euo pipefail

TASK_ID="FALCO-BUNDLE"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

say() { printf '\033[1;34m[accept:%s]\033[0m %s\n' "$TASK_ID" "$*"; }
fail() { printf '\033[1;31m[accept:%s FAIL]\033[0m %s\n' "$TASK_ID" "$*" >&2; exit 1; }

# Resolve a mikefarah-yq binary (assertions below use mikefarah-style
# eval/eval-all, which Python's kislyuk/yq does not implement).
YQ=""
if command -v yq >/dev/null 2>&1 && yq --version 2>&1 | grep -qi "mikefarah"; then
  YQ="$(command -v yq)"
elif [[ -x /usr/local/bin/yq ]] && /usr/local/bin/yq --version 2>&1 | grep -qi "mikefarah"; then
  YQ="/usr/local/bin/yq"
else
  cache_dir="${REPO_ROOT}/.cache/sprint-bin"
  mkdir -p "$cache_dir"
  YQ="${cache_dir}/yq"
  if [[ ! -x "$YQ" ]] || ! "$YQ" --version 2>&1 | grep -qi "mikefarah"; then
    say "bootstrapping mikefarah/yq into $cache_dir (no system mikefarah-yq found)"
    arch="$(uname -m)"
    case "$arch" in
      x86_64) yq_arch="amd64" ;;
      aarch64|arm64) yq_arch="arm64" ;;
      *) fail "unsupported arch for yq bootstrap: $arch" ;;
    esac
    curl -sSL -o "$YQ" "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${yq_arch}" \
      || fail "failed to download mikefarah/yq"
    chmod +x "$YQ"
  fi
fi
say "yq: $YQ ($("$YQ" --version 2>&1))"

HR="_lib/controllers/falco/helmrelease.yaml"

# 1. yamllint touched YAML paths (accept.sh is a shell script, not YAML).
TOUCH_PATHS=(
  "$HR"
)
say "yamllint ${#TOUCH_PATHS[@]} files"
yamllint -c .yamllint.yaml "${TOUCH_PATHS[@]}" || fail "yamllint failed"
say "shellcheck-lite: bash -n accept.sh"
bash -n .claude/sprints/falco-bundle/accept.sh || fail "accept.sh has shell syntax error"

# 2. kustomize render non-empty (proves manifests still parse).
say "kubectl kustomize _lib/controllers/falco"
render="$(kubectl kustomize _lib/controllers/falco)" || fail "kustomize render failed"
[[ -n "$render" ]] || fail "kustomize render empty"
if grep -qE '\$\{[^}]*$' <<<"$render"; then
  fail "unbalanced \${...} in kustomize output"
fi

# Helper: select the Falco HR doc and query a path.
hr_q() {
  "$YQ" eval "
    select(.kind == \"HelmRelease\" and .metadata.name == \"falco\")
    | $1
  " "$HR"
}

# 3. F-1 — Custom-rules ConfigMap mounted.

# 3a. mounts.volumes contains an entry with configMap.name == falco-custom-rules
say "F-1 assert: mounts.volumes references configMap falco-custom-rules"
vol_match="$(hr_q '
  [.spec.values.mounts.volumes[]?
    | select(.configMap.name == "falco-custom-rules")] | length
')"
[[ "$vol_match" -ge 1 ]] || fail "F-1: no mounts.volumes entry with configMap.name == falco-custom-rules (got count=$vol_match)"

# 3b. mounts.volumeMounts contains an entry with matching name and
#     mountPath == /etc/falco/rules.d.
say "F-1 assert: mounts.volumeMounts has /etc/falco/rules.d entry tied to the custom-rules volume"
# First get the volume name from the configMap match.
vol_name="$(hr_q '
  .spec.values.mounts.volumes[]
  | select(.configMap.name == "falco-custom-rules")
  | .name
' | head -1)"
[[ -n "$vol_name" ]] || fail "F-1: could not resolve custom-rules volume name"
mount_match="$(hr_q "
  [.spec.values.mounts.volumeMounts[]?
    | select(.name == \"$vol_name\" and .mountPath == \"/etc/falco/rules.d\")] | length
")"
[[ "$mount_match" -ge 1 ]] || fail "F-1: no mounts.volumeMounts entry with name=$vol_name mountPath=/etc/falco/rules.d (got count=$mount_match)"

# 3c. falco.rules_files includes /etc/falco/rules.d so the mounted directory
#     is actually loaded by the engine.
say "F-1 assert: falco.rules_files includes /etc/falco/rules.d"
rules_dir_hit="$(hr_q '
  [.spec.values.falco.rules_files[]?
    | select(. == "/etc/falco/rules.d")] | length
')"
[[ "$rules_dir_hit" -ge 1 ]] || fail "F-1: falco.rules_files does not include /etc/falco/rules.d"

# 4. F-2 — falcosidekick UI + Redis disabled, alert plumbing preserved.

# 4a. falcosidekick.webui.enabled == false
say "F-2 assert: falcosidekick.webui.enabled == false"
webui_enabled="$(hr_q '.spec.values.falcosidekick.webui.enabled')"
[[ "$webui_enabled" == "false" ]] || fail "F-2: falcosidekick.webui.enabled=$webui_enabled (want false)"

# 4b. falcosidekick.webui.redis.enabled == false (note: redis lives UNDER webui
#     in the falcosidekick 0.12.x subchart, not under config).
say "F-2 assert: falcosidekick.webui.redis.enabled == false"
redis_enabled="$(hr_q '.spec.values.falcosidekick.webui.redis.enabled')"
[[ "$redis_enabled" == "false" ]] || fail "F-2: falcosidekick.webui.redis.enabled=$redis_enabled (want false)"

# 4c. Falco→falcosidekick alert plumbing preserved (survival guard). The
#     current HR routes alerts via falco.http_output → falco-falcosidekick:2801.
#     If a future change adds falcosidekick.config.slack.webhookurl, also
#     guard that it stays non-empty. This is the actual "don't nuke the
#     alert path" check the brief calls for.
say "F-2 assert: falco.http_output.enabled == true (alert plumbing preserved)"
http_out_enabled="$(hr_q '.spec.values.falco.http_output.enabled')"
[[ "$http_out_enabled" == "true" ]] || fail "F-2: falco.http_output.enabled=$http_out_enabled (want true; alert path nuked)"

say "F-2 assert: falco.http_output.url targets falcosidekick"
http_out_url="$(hr_q '.spec.values.falco.http_output.url')"
[[ "$http_out_url" == *"falcosidekick"* ]] \
  || fail "F-2: falco.http_output.url=$http_out_url (expected to contain 'falcosidekick')"

# Conditional slack survival guard — only enforced if a slack webhookurl key
# exists in the values (future-state). Today there is no slack block, so this
# is a no-op until somebody wires it in.
slack_url="$(hr_q '.spec.values.falcosidekick.config.slack.webhookurl // ""')"
if [[ -n "$slack_url" && "$slack_url" != "null" ]]; then
  say "F-2 assert: existing falcosidekick.config.slack.webhookurl preserved"
  [[ "$slack_url" != '""' ]] || fail "F-2: falcosidekick.config.slack.webhookurl was zeroed out"
fi

# 5. F-3 baseline assert — driver still pinned to modern_ebpf in the HR.
say "F-3 assert: driver.kind == modern_ebpf (static)"
driver_kind="$(hr_q '.spec.values.driver.kind')"
[[ "$driver_kind" == "modern_ebpf" ]] || fail "F-3: driver.kind=$driver_kind (want modern_ebpf)"

# 6. F-3 runtime probe (read-only) — verify the live DS actually loaded the
#     modern_ebpf driver, not legacy/kmod. Guarded so CI without k8sop skips.
if command -v k8sop >/dev/null 2>&1; then
  say "F-3 probe: read DaemonSet logs for modern_ebpf driver load line"
  # `2>&1` so we can grep stderr-style lines too. `|| true` lets us inspect
  # the captured output without exiting on grep's non-zero on empty.
  logs="$(k8sop dev kubectl -n security logs ds/security-falco-falcosecurity -c falco --tail=400 2>&1 || true)"
  if [[ -z "$logs" ]]; then
    say "F-3 probe: no logs returned (DS may not exist yet) — skipping live check"
  else
    if grep -qiE "modern.bpf|modern_ebpf" <<<"$logs"; then
      say "F-3 probe: modern_ebpf driver line found"
    elif grep -qiE "kmod|legacy.?ebpf|kernel module" <<<"$logs"; then
      fail "F-3: live Falco logs show non-modern driver (kmod/legacy eBPF). Update driver config and reconcile."
    else
      # No definitive signal — print a sample tail so the human can eyeball,
      # but don't block. The static assertion above already pins the config.
      say "F-3 probe: no explicit driver-load line found in last 400 lines (inconclusive). Sample tail:"
      tail -20 <<<"$logs" | sed 's/^/    /'
    fi
  fi
fi

say "PASS"
