#!/usr/bin/env bash
# Acceptance test for O-7 — remaining custom alerts.
#
# O-7 adds three alerts to the existing custom PrometheusRule:
#   - CertExpiringSoon      (cert-manager certificate expiry)
#   - PVCNearFull           (kubelet volume stats, excluding *-dumps-pvc)
#   - GatusEndpointDown     (gatus_results_endpoint_success == 0)
#
# This script validates the static state on disk. Pure read-only — no
# kubectl apply / flux reconcile / helm install / git push. Idempotent.
# Exits 0 on pass, non-zero on fail.
#
# Wrapper rule (CLAUDE.md): cluster probes are guarded behind
# `command -v k8sop` so CI (no wrapper) skips cleanly.

set -euo pipefail

TASK_ID="O-7"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

say() { printf '\033[1;34m[accept:%s]\033[0m %s\n' "$TASK_ID" "$*"; }
fail() { printf '\033[1;31m[accept:%s FAIL]\033[0m %s\n' "$TASK_ID" "$*" >&2; exit 1; }

# Resolve a mikefarah-yq binary (Python kislyuk/yq is the system default and
# does not implement mikefarah-style eval/eval-all). CI installs mikefarah yq
# at /usr/local/bin/yq; locally only Python yq is usually on PATH. Detect, and
# if no mikefarah-style yq is anywhere, download a cached copy under .cache/.
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

# 1. yamllint touched paths.
TOUCH_PATHS=(
  "_lib/observability/kube-prometheus-stack/prometheusrule-custom.yaml"
  ".claude/sprints/o-7/accept.sh"
)
say "yamllint ${#TOUCH_PATHS[@]} files"
# accept.sh is a shell script, not YAML — only lint the YAML file.
yamllint -c .yamllint.yaml "${TOUCH_PATHS[0]}" || fail "yamllint failed"

# 2. kustomize render — proves the kustomization still produces valid YAML.
KUSTOMIZE_TARGET="_lib/observability/kube-prometheus-stack"
say "kubectl kustomize $KUSTOMIZE_TARGET"
RENDER="$(kubectl kustomize "$KUSTOMIZE_TARGET")" || fail "kustomize render failed"
[[ -n "$RENDER" ]] || fail "kustomize render empty"
# Leftover ${VAR} is fine (Flux substitutes at reconcile). But unbalanced
# `${...` (no closing brace) indicates a typo.
if grep -qE '\$\{[^}]*$' <<<"$RENDER"; then
  fail "unbalanced \${...} in kustomize output"
fi

# 3. Manifest invariants — exactly one custom PrometheusRule renders.
say "assert: exactly one custom PrometheusRule renders"
pr_count="$(echo "$RENDER" | "$YQ" eval-all '
  select(.kind == "PrometheusRule" and .metadata.name == "home-0ps-custom-rules") | .metadata.name
' - | wc -l)"
[[ "$pr_count" == "1" ]] || fail "expected 1 PrometheusRule 'home-0ps-custom-rules', got $pr_count"

# Extract the custom PrometheusRule as its own doc for further assertions.
PR_DOC="$(echo "$RENDER" | "$YQ" eval-all '
  select(.kind == "PrometheusRule" and .metadata.name == "home-0ps-custom-rules")
' -)"

# 3a. Survival guard — the two existing rules must still be present.
say "assert: existing rules CNPGBackupStale + CNPGDumpCronJobStale preserved"
for existing in CNPGBackupStale CNPGDumpCronJobStale PodOOMKilled FluxKustomizationNotReady FluxHelmReleaseNotReady FluxResourceSuspended; do
  hit="$(echo "$PR_DOC" | "$YQ" eval '
    [.spec.groups[].rules[] | select(.alert == "'"$existing"'")] | length
  ' -)"
  [[ "$hit" -ge 1 ]] || fail "existing alert '$existing' missing — O-7 must add, not replace"
done

# 3b. Three new alerts exist, each with a severity label set to warning|critical.
NEW_ALERTS=(CertExpiringSoon PVCNearFull GatusEndpointDown)
for alert in "${NEW_ALERTS[@]}"; do
  say "assert: new alert '$alert' exists with severity label"
  cnt="$(echo "$PR_DOC" | "$YQ" eval '
    [.spec.groups[].rules[] | select(.alert == "'"$alert"'")] | length
  ' -)"
  [[ "$cnt" -ge 1 ]] || fail "new alert '$alert' not found"
  # Every variant of $alert must have a severity label set to warning|critical.
  bad="$(echo "$PR_DOC" | "$YQ" eval '
    [.spec.groups[].rules[]
      | select(.alert == "'"$alert"'")
      | select((.labels.severity // "") | (. != "warning" and . != "critical"))
    ] | length
  ' -)"
  [[ "$bad" == "0" ]] || fail "alert '$alert' has $bad rule(s) missing severity=warning|critical"
done

# 3c. CertExpiringSoon must reference the cert-manager expiration timestamp
# metric. Live cluster uses `certmanager_certificate_expiration_timestamp_seconds`
# (no underscore between cert and manager — verified via the in-cluster
# Prometheus /api/v1/label/__name__/values endpoint on 2026-05-28).
say "assert: CertExpiringSoon expr references certmanager_certificate_expiration_timestamp_seconds"
echo "$PR_DOC" | "$YQ" eval '
  [.spec.groups[].rules[] | select(.alert == "CertExpiringSoon") | .expr] | .[]
' - | grep -q "certmanager_certificate_expiration_timestamp_seconds" \
  || fail "CertExpiringSoon expr does not reference certmanager_certificate_expiration_timestamp_seconds"

# Both severity tiers (warning + critical) must be present.
for sev in warning critical; do
  say "assert: CertExpiringSoon has a $sev-severity variant"
  cnt="$(echo "$PR_DOC" | "$YQ" eval '
    [.spec.groups[].rules[] | select(.alert == "CertExpiringSoon" and .labels.severity == "'"$sev"'")] | length
  ' -)"
  [[ "$cnt" -ge 1 ]] || fail "CertExpiringSoon missing $sev-severity variant"
done

# 3d. PVCNearFull must reference both kubelet_volume_stats_* metrics and
# exclude *-dumps-pvc PVCs via a persistentvolumeclaim regex filter.
say "assert: PVCNearFull expr references kubelet_volume_stats_available_bytes + capacity_bytes"
pvc_exprs="$(echo "$PR_DOC" | "$YQ" eval '
  [.spec.groups[].rules[] | select(.alert == "PVCNearFull") | .expr] | .[]
' -)"
grep -q "kubelet_volume_stats_available_bytes" <<<"$pvc_exprs" \
  || fail "PVCNearFull expr missing kubelet_volume_stats_available_bytes"
grep -q "kubelet_volume_stats_capacity_bytes" <<<"$pvc_exprs" \
  || fail "PVCNearFull expr missing kubelet_volume_stats_capacity_bytes"

say "assert: PVCNearFull excludes *-dumps-pvc via persistentvolumeclaim filter"
grep -qE 'persistentvolumeclaim!~"[^"]*dumps-pvc[^"]*"' <<<"$pvc_exprs" \
  || fail "PVCNearFull expr missing persistentvolumeclaim!~\".*dumps-pvc\" exclusion"

# Both severity tiers (warning + critical) must be present.
for sev in warning critical; do
  say "assert: PVCNearFull has a $sev-severity variant"
  cnt="$(echo "$PR_DOC" | "$YQ" eval '
    [.spec.groups[].rules[] | select(.alert == "PVCNearFull" and .labels.severity == "'"$sev"'")] | length
  ' -)"
  [[ "$cnt" -ge 1 ]] || fail "PVCNearFull missing $sev-severity variant"
done

# 3e. GatusEndpointDown references gatus_results_endpoint_success (verified
# live via Prometheus /api/v1/label/__name__/values on 2026-05-28; labels
# include `key` for endpoint identity).
say "assert: GatusEndpointDown expr references gatus_results_endpoint_success"
echo "$PR_DOC" | "$YQ" eval '
  [.spec.groups[].rules[] | select(.alert == "GatusEndpointDown") | .expr] | .[]
' - | grep -q "gatus_results_endpoint_success" \
  || fail "GatusEndpointDown expr does not reference gatus_results_endpoint_success"

# 4. Optional read-only cluster probe — confirms the metrics referenced by the
# new rules are actually emitted in the live cluster. Guarded so CI skips.
if command -v k8sop >/dev/null 2>&1; then
  say "k8sop probe: confirm referenced metrics exist in Prometheus"
  metrics_json="$(k8sop dev kubectl -n monitoring exec prometheus-kps-prometheus-0 -c prometheus -- \
    wget -qO- "http://localhost:9090/api/v1/label/__name__/values" 2>/dev/null || true)"
  if [[ -n "$metrics_json" ]]; then
    for m in certmanager_certificate_expiration_timestamp_seconds \
             kubelet_volume_stats_available_bytes \
             kubelet_volume_stats_capacity_bytes \
             gatus_results_endpoint_success; do
      if ! echo "$metrics_json" | jq -e --arg m "$m" '.data | index($m)' >/dev/null 2>&1; then
        say "warn: metric '$m' not currently emitted — alert will not fire until it is"
      fi
    done
  else
    say "warn: could not probe Prometheus (skipping metric existence sanity)"
  fi
fi

say "PASS"
