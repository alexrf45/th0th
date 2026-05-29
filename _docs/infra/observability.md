# Observability

Metrics stay in-cluster; logs are offloaded to a small bare-metal Loki host so
retention survives cluster rebuilds.

> **Example values.** `10.10.20.30` (the Loki host) and `10.10.20.10` (the NAS
> scrape target) are placeholders.

**Layer:** `observability` (Flux Kustomization, depends on storage, secrets,
networking).

## Stack

| Signal | Component | Where | Storage / retention |
| --- | --- | --- | --- |
| Metrics | kube-prometheus-stack `78.0.0` (Prometheus, Alertmanager, Grafana, node-exporter, kube-state-metrics) | in-cluster `monitoring` ns | Prometheus 50Gi iSCSI / 15d; Alertmanager 5Gi; Grafana 5Gi |
| Logs | Grafana Alloy `1.4.0` DaemonSet → **off-cluster Loki** | Alloy in-cluster; Loki on `10.10.20.30` | filesystem |

CRDs come from `prometheus-operator-crds` (the chart sets `crds.enabled: false`
per the [CRD pattern](secrets-pki.md) — operators whose CRs Flux reconciles
shouldn't also install their own CRDs).

## Where it lives

| Path | What |
| --- | --- |
| `_lib/observability/kube-prometheus-stack/helmrelease.yaml` | Prometheus/Grafana/Alertmanager; Grafana OIDC (`auth.generic_oauth`); Alertmanager Slack routing; `defaultRules.create: true` |
| `_lib/observability/kube-prometheus-stack/external-secret{,-oidc,-slack}.yaml` | Grafana admin, OIDC client, Slack webhook (all ESO ← 1Password) |
| `_lib/observability/alloy/{helmrelease,configmap}.yaml` | log DaemonSet + config |
| `_lib/observability/tailscale-egress/loki-egress-service.yaml` | cluster → Loki transport |
| `_lib/observability/scrape-configs/` | external scrape targets (NAS `ScrapeConfig`, Tailscale `PodMonitor`) |

## Logs: why off-cluster

Loki runs on a dedicated low-power host (`10.10.20.30`) so log retention is
decoupled from cluster lifecycle and can use a large spare partition. The cluster
→ Loki transport is **Tailscale** (an egress service / sidecar on the host).
Alloy ships logs from every node; the Loki backend is plain filesystem.

> **Lesson — log shippers must run as root.** `capabilities.add` lands in the
> *bounding* set only on non-root pods, so Alloy/Promtail-style shippers need
> `runAsUser: 0` to read `/var/log/pods`. See
> [Best practices](../guides/best-practices.md#log-shippers-need-root).

## Auth & alerting

- **Grafana OIDC** via Authentik (`auth.generic_oauth`), roles mapped from
  entitlements (Admins/Editors/Viewers), credentials from a `grafana-oidc` ESO
  secret, with the local admin retained for break-glass. Setup:
  [Authentik](../apps/authentik.md#wiring-an-oidc-consumer-grafana).
- **Alertmanager → Slack** (`slack-critical`/`slack-warning` receivers, a route
  tree, inhibit rules) plus the chart's `defaultRules`.

## Scrape targets

In-cluster `ServiceMonitor`s are auto-discovered. External targets use CRs: the
NAS via `ScrapeConfig`, the Tailscale operator via `PodMonitor`, 1Password
Connect via `ServiceMonitor`.

## Gotchas

- **Grafana RWO PVC + rolling update = `Multi-Attach`** when the new pod lands on
  a different node. Delete the old pod to break the deadlock; the real fix is
  `grafana.deploymentStrategy.type: Recreate`.
- **Grafana OIDC's in-cluster back-channel** depends on the CoreDNS split-horizon
  forward resolving the Authentik hostname ([DNS](dns.md)).
