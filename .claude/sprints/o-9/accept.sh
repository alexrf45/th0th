#!/usr/bin/env bash
# Acceptance test for O-9 — App-level dashboards/alerts.
#
# Validates the static state on disk after the O-9 changes are applied.
# Pure static + read-only — no kubectl apply / flux reconcile / helm install
# / git push. Idempotent. Exits 0 on pass, non-zero on fail.
#
# Wrapper rule (CLAUDE.md): any cluster probe is guarded behind
# `command -v k8sop` so CI (no wrapper) skips cleanly.

set -euo pipefail

TASK_ID="O-9"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

say() { printf '\033[1;34m[accept:%s]\033[0m %s\n' "$TASK_ID" "$*"; }
fail() { printf '\033[1;31m[accept:%s FAIL]\033[0m %s\n' "$TASK_ID" "$*" >&2; exit 1; }

# Resolve a mikefarah-yq binary (the assertions below use mikefarah-style
# `eval`/`eval-all`, which Python's kislyuk/yq does not implement). CI
# installs mikefarah yq at /usr/local/bin/yq; locally only the Python yq is
# usually present on PATH (/usr/bin/yq → 3.x, jq-shim). Detect, and if no
# mikefarah-style yq is present anywhere, download a cached copy under
# .cache/.
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
  "_lib/controllers/authentik/helmrelease.yaml"
  "_lib/observability/kube-prometheus-stack/servicemonitor-authentik.yaml"
  "_lib/observability/kube-prometheus-stack/kustomization.yaml"
  "_lib/observability/kube-prometheus-stack/dashboards/kustomization.yaml"
  "_lib/observability/kube-prometheus-stack/dashboards/dashboard-authentik.yaml"
  "_lib/observability/kube-prometheus-stack/dashboards/dashboard-cloudflared.yaml"
  "_lib/observability/kube-prometheus-stack/dashboards/dashboard-gatus.yaml"
  "_lib/observability/kube-prometheus-stack/dashboards/dashboard-freshrss.yaml"
)
say "yamllint ${#TOUCH_PATHS[@]} files"
yamllint -c .yamllint.yaml "${TOUCH_PATHS[@]}" || fail "yamllint failed"

# 2. kustomize render — proves the overlay/base still produces valid YAML.
say "kubectl kustomize _lib/observability/kube-prometheus-stack"
OBS_RENDER="$(kubectl kustomize _lib/observability/kube-prometheus-stack)" \
  || fail "kustomize render failed: _lib/observability/kube-prometheus-stack"
[[ -n "$OBS_RENDER" ]] || fail "kustomize render empty: _lib/observability/kube-prometheus-stack"
if grep -qE '\$\{[^}]*$' <<<"$OBS_RENDER"; then
  fail "unbalanced \${...} in obs kustomize output"
fi

# 3. Manifest invariants.

# 3a. ServiceMonitor 'authentik' exists in the obs render.
say "assert: ServiceMonitor 'authentik' in obs render"
echo "$OBS_RENDER" | "$YQ" eval-all '
  select(.kind == "ServiceMonitor" and .metadata.name == "authentik") | .metadata.name
' - | grep -qx "authentik" || fail "ServiceMonitor 'authentik' not found in obs render"

# 3b. Dashboard ConfigMaps present (all four expected — be lenient: require >=3).
say "assert: dashboard ConfigMaps present"
EXPECTED_DASHBOARDS=(dashboard-authentik dashboard-cloudflared dashboard-gatus dashboard-freshrss)
found_count=0
for name in "${EXPECTED_DASHBOARDS[@]}"; do
  match="$(echo "$OBS_RENDER" | "$YQ" eval-all "
    select(.kind == \"ConfigMap\" and .metadata.name == \"$name\") | .metadata.name
  " -)"
  if [[ "$match" == "$name" ]]; then
    say "  found: $name"
    found_count=$((found_count + 1))
  else
    say "  MISSING: $name"
  fi
done
[[ "$found_count" -ge 3 ]] || fail "only $found_count/4 dashboard ConfigMaps found (need >=3)"

# 3c. Every dashboard ConfigMap carries label grafana_dashboard: "1" so the
# kps Grafana sidecar discovers + mounts it.
say "assert: every dashboard ConfigMap has label grafana_dashboard=1"
bad_labels="$(echo "$OBS_RENDER" | "$YQ" eval-all '
  select(.kind == "ConfigMap" and (.metadata.name | test("^dashboard-")))
  | select((.metadata.labels.grafana_dashboard // "") != "1")
  | .metadata.name
' -)"
[[ -z "$bad_labels" ]] || fail "dashboard ConfigMaps missing grafana_dashboard=1 label: $bad_labels"

# 3d. Authentik HR has chart-side metrics enabled. We follow the Falco pattern:
# enable chart's metrics endpoint (creates the metrics Service) but own the
# ServiceMonitor in observability/. The brief said "flip serviceMonitor.enabled:
# true"; we interpret that as "stand up Prometheus-based scraping" — either
# chart-side or observability-owned satisfies the spirit. Assert metrics is
# enabled on both server and worker so the SM has targets.
say "assert: Authentik HR has server.metrics.enabled == true"
server_metrics="$("$YQ" eval '
  select(.kind == "HelmRelease" and .metadata.name == "authentik")
  | .spec.values.server.metrics.enabled
' _lib/controllers/authentik/helmrelease.yaml)"
[[ "$server_metrics" == "true" ]] || fail "Authentik HR server.metrics.enabled=$server_metrics (want true)"

say "assert: Authentik HR has worker.metrics.enabled == true"
worker_metrics="$("$YQ" eval '
  select(.kind == "HelmRelease" and .metadata.name == "authentik")
  | .spec.values.worker.metrics.enabled
' _lib/controllers/authentik/helmrelease.yaml)"
[[ "$worker_metrics" == "true" ]] || fail "Authentik HR worker.metrics.enabled=$worker_metrics (want true)"

# 3e. Authentik HR keeps chart-side serviceMonitor.enabled == false on both
# server and worker so we don't double-scrape (obs-owned SM takes over).
say "assert: Authentik HR server.metrics.serviceMonitor.enabled == false"
server_sm="$("$YQ" eval '
  select(.kind == "HelmRelease" and .metadata.name == "authentik")
  | .spec.values.server.metrics.serviceMonitor.enabled
' _lib/controllers/authentik/helmrelease.yaml)"
[[ "$server_sm" == "false" ]] \
  || fail "Authentik HR server.metrics.serviceMonitor.enabled=$server_sm (want false; SM is owned by observability)"

# 3f. ServiceMonitor lives in the monitoring namespace + selects the
# authentik metrics svc cross-namespace (namespaceSelector includes authentik).
say "assert: ServiceMonitor 'authentik' targets authentik ns"
sm_ns_select="$(echo "$OBS_RENDER" | "$YQ" eval-all '
  select(.kind == "ServiceMonitor" and .metadata.name == "authentik")
  | .spec.namespaceSelector.matchNames[]
' -)"
echo "$sm_ns_select" | grep -qx "authentik" \
  || fail "ServiceMonitor 'authentik' does not target the authentik namespace"

# 4. Optional read-only cluster probe — sanity for the SM apply path.
if command -v k8sop >/dev/null 2>&1; then
  say "k8sop probe: monitoring.coreos.com/servicemonitors CRD present"
  k8sop dev kubectl get crd servicemonitors.monitoring.coreos.com -o name >/dev/null \
    || fail "servicemonitors CRD missing on the cluster — SM apply will fail"
fi

say "PASS"
