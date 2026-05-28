#!/usr/bin/env bash
# Acceptance test for H-3 — Falco enablement.
#
# Validates the static state on disk after the H-3 changes are applied.
# Pure static + read-only — no kubectl apply / flux reconcile / helm install
# / git push. Idempotent. Exits 0 on pass, non-zero on fail.
#
# Wrapper rule (CLAUDE.md): any cluster probe is guarded behind
# `command -v k8sop` so CI (no wrapper) skips cleanly.

set -euo pipefail

TASK_ID="H-3"
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
  "_lib/controllers/falco/helmrelease.yaml"
  "_lib/controllers/falco/helmrepository.yaml"
  "_lib/controllers/falco/kustomization.yaml"
  "_lib/controllers/falco/namespace.yaml"
  "_lib/controllers/kustomization.yaml"
  "_lib/security/kustomization.yaml"
  "_lib/security/falco-rules/kustomization.yaml"
  "_lib/security/falco-rules/configmap-custom-rules.yaml"
  "_lib/observability/kube-prometheus-stack/servicemonitor-falco.yaml"
  "_lib/observability/kube-prometheus-stack/kustomization.yaml"
)
say "yamllint ${#TOUCH_PATHS[@]} files"
yamllint -c .yamllint.yaml "${TOUCH_PATHS[@]}" || fail "yamllint failed"

# 2. kustomize renders — proves the overlays/bases still produce valid YAML.
KUSTOMIZE_TARGETS=(
  "_lib/controllers/falco"
  "_lib/security/falco-rules"
  "_lib/security"
  "_lib/observability/kube-prometheus-stack"
)
declare -A RENDERS
for target in "${KUSTOMIZE_TARGETS[@]}"; do
  say "kubectl kustomize $target"
  out="$(kubectl kustomize "$target")" || fail "kustomize render failed: $target"
  [[ -n "$out" ]] || fail "kustomize render empty: $target"
  # Leftover ${VAR} is fine (Flux substitutes at reconcile). But unbalanced
  # `${...` (no closing brace) indicates a typo.
  if grep -qE '\$\{[^}]*$' <<<"$out"; then
    fail "unbalanced \${...} in kustomize output: $target"
  fi
  RENDERS[$target]="$out"
done

# 3. Manifest invariants.

# 3a. _lib/controllers/falco renders a HelmRelease named "falco".
say "assert: HelmRelease 'falco' in _lib/controllers/falco"
echo "${RENDERS[_lib/controllers/falco]}" | "$YQ" eval-all '
  select(.kind == "HelmRelease" and .metadata.name == "falco") | .metadata.name
' - | grep -qx "falco" || fail "HelmRelease 'falco' not found in _lib/controllers/falco render"

# 3b. _lib/security includes the falco-rules path (uncommented).
say "assert: _lib/security/kustomization.yaml includes ./falco-rules"
grep -E '^\s*-\s*\./falco-rules\s*$' _lib/security/kustomization.yaml >/dev/null \
  || fail "_lib/security/kustomization.yaml does not include ./falco-rules"

# 3c. _lib/controllers includes the falco path (uncommented).
say "assert: _lib/controllers/kustomization.yaml includes ./falco"
grep -E '^\s*-\s*\./falco\s*$' _lib/controllers/kustomization.yaml >/dev/null \
  || fail "_lib/controllers/kustomization.yaml does not include ./falco"

# 3d. _lib/security render carries the falco-rules ConfigMap through.
say "assert: falco-rules ConfigMap present in _lib/security render"
echo "${RENDERS[_lib/security]}" | "$YQ" eval-all '
  select(.kind == "ConfigMap" and (.metadata.name | test("^falco-custom-rules"))) | .kind
' - | grep -qx "ConfigMap" \
  || fail "falco-custom-rules ConfigMap not present in _lib/security render"

# 3e. observability render contains a ServiceMonitor named "falco".
say "assert: ServiceMonitor 'falco' in _lib/observability/kube-prometheus-stack"
echo "${RENDERS[_lib/observability/kube-prometheus-stack]}" | "$YQ" eval-all '
  select(.kind == "ServiceMonitor" and .metadata.name == "falco") | .metadata.name
' - | grep -qx "falco" || fail "ServiceMonitor 'falco' not found in observability render"

# 3f. The Falco HR's values block does NOT enable the chart's own ServiceMonitor
# (we own the ServiceMonitor in observability/). Falco's `serviceMonitor.create`
# default is false — make sure no overlay flipped it to true.
say "assert: Falco HR does not enable chart-side serviceMonitor.create"
sm_create="$("$YQ" eval '
  select(.kind == "HelmRelease" and .metadata.name == "falco")
  | .spec.values.serviceMonitor.create // false
' _lib/controllers/falco/helmrelease.yaml)"
[[ "$sm_create" == "false" ]] || fail "Falco HR has serviceMonitor.create=$sm_create (want false; SM is owned by observability)"

# 3g. Falco HR uses modern_ebpf driver (verified on Talos per H-3 brief).
say "assert: Falco HR driver.kind == modern_ebpf"
driver_kind="$("$YQ" eval '
  select(.kind == "HelmRelease" and .metadata.name == "falco")
  | .spec.values.driver.kind
' _lib/controllers/falco/helmrelease.yaml)"
[[ "$driver_kind" == "modern_ebpf" ]] || fail "Falco HR driver.kind=$driver_kind (want modern_ebpf)"

# 3h. Falco HR enables metrics + falco.metrics service so the SM has a target.
say "assert: Falco HR has metrics.enabled == true"
metrics_enabled="$("$YQ" eval '
  select(.kind == "HelmRelease" and .metadata.name == "falco")
  | .spec.values.metrics.enabled
' _lib/controllers/falco/helmrelease.yaml)"
[[ "$metrics_enabled" == "true" ]] || fail "Falco HR metrics.enabled=$metrics_enabled (want true)"

# 3i. CRD-ownership rule check.
# The Falco chart (falcosecurity/falco 8.0.0) ships NO CRDs of its own. The
# only CRD it consumes (monitoring.coreos.com/ServiceMonitor) is already owned
# by global/crds/prometheus-operator-crds/. Therefore no `global/crds/falco/`
# directory is needed and the .claude/rules/crds.md rule is satisfied
# vacuously. Sanity-check: the HR must not declare a CRD-installation flag
# whose true value would conflict with the rule (Falco chart has no such
# flag; this is a forward guard).
say "assert: Falco HR has no chart-level CRD-install flag set true"
crd_install="$("$YQ" eval '
  select(.kind == "HelmRelease" and .metadata.name == "falco")
  | (.spec.values.crds.create // .spec.values.crds.enabled // .spec.values.installCRDs // false)
' _lib/controllers/falco/helmrelease.yaml)"
[[ "$crd_install" == "false" ]] || fail "Falco HR sets chart-level CRD install to $crd_install (want false; CRD lifecycle belongs in global/crds/ per .claude/rules/crds.md)"

# 4. Optional read-only cluster probe — sanity for the SM apply path.
if command -v k8sop >/dev/null 2>&1; then
  say "k8sop probe: monitoring.coreos.com/servicemonitors CRD present"
  k8sop dev kubectl get crd servicemonitors.monitoring.coreos.com -o name >/dev/null \
    || fail "servicemonitors CRD missing on the cluster — SM apply will fail"
fi

say "PASS"
