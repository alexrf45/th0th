# Service Status (Gatus) — Sprint Plan

> Created: 2026-05-25. Owner: alexrf45.
> Goal: deploy **Gatus** as the service status engine — server-side health,
> uptime history, internal + public status pages.
> Decisions locked 2026-05-25 ([ADR-0007](decisions/0007-service-status-engine.md)):
> Gatus; exposed **internal + public** (Cloudflare Tunnel); plan tracked here.
> Updated 2026-05-26: docs-site (MkDocs wiki) retired; **G3 (rebuild
> `_docs/status.md`) dropped** — Gatus is the sole status surface.

## Why

The old services page (`_docs/status.md`, now removed with the docs-site) probed
from the **viewer's browser** — on-LAN only, no HTTP status, no uptime history —
plus a **hand-maintained Platform table** that drifted (claimed Talos `v1.13.0`
vs live `v1.12.8`). It already proposed Gatus as the fix; this sprint builds it
and ships it as a first-class app.

## Scope

- **In:** Gatus app (GitOps), internal exposure (Cilium Gateway) + public
  exposure (Cloudflare Tunnel), Homer tile, alerting (follow-up).
- **Prerequisite (G0):** a Cloudflare Tunnel — net-new infra, stood up via
  Terraform in `terraform/cloudflare-tunnel/`.
- **Out:** replacing Grafana/Prometheus (Gatus complements, not replaces them);
  rebuilding `_docs/status.md` (the docs-site is gone).

**Guardrails to honor** (established patterns): RQ + LimitRange per namespace
(H-4); explicit container resources; explicit `runAsUser` (Kyverno mutation
gotcha); CCNP default-deny + `reserved:ingress` for the gateway; ServiceMonitor
for `/metrics`; `kube`/`k8sop` wrappers only; verify endpoints against the live
cluster, don't guess.

---

## Sprint G0 — Cloudflare Tunnel prerequisite (blocks public board)

> Net-new exposure path — the repo has no `cloudflared` today. May deserve its
> own ADR if it grows beyond Gatus.

**Approach chosen:** **remotely-managed (token-based)** tunnel, **created and
owned by Terraform** (`terraform/cloudflare-tunnel/`, its own S3 state so a
cluster rebuild never destroys it). Terraform creates the tunnel
(`config_src = "cloudflare"`), reads the connector token, and **writes it into
the 1Password item** `cf_tunnel_home-0ps.com` (field `tunnel-token`). The cluster
ExternalSecret ingests that item; cloudflared runs with the single `TUNNEL_TOKEN`.
Public-hostname ingress is managed Cloudflare-side (added in G2 via
`cloudflare_zero_trust_tunnel_cloudflared_config` + a DNS record) — no manual
dashboard steps and no `config.yaml`.

**Token needed:** a Cloudflare **API token** for Terraform — account-scoped
**Cloudflare Tunnel: Edit** (+ **Zone: DNS: Edit** for the G2 DNS record),
ideally an account-owned token. This is separate from the cert-manager DNS-01
token (`cf_token_home-0ps.com`). 1Password writes use the existing service-account
token (same one `terraform/dev` uses).

| ID | Task | Status | Notes |
| -- | ---- | ------ | ----- |
| ~~G0-1~~ | ~~Design the tunnel~~ | ✅ Done | Token-based + Terraform-managed (own state) |
| ~~G0-2~~ | ~~Cluster manifests: Deployment + ExternalSecret + namespace/PSA + RQ/LimitRange~~ | ✅ Done | `_lib/networking/cloudflared/`; cloudflared `2026.5.1`, 2 replicas (HA), metrics:2000, RO-rootfs/nonroot. Token via ESO from `cf_tunnel_home-0ps.com` → `tunnel-token` |
| ~~G0-3~~ | ~~Terraform: tunnel + token data source + onepassword_item~~ | ✅ Done | `terraform/cloudflare-tunnel/` (cloudflare 5.19.1, onepassword 3.3.1); `fmt`+`validate` green |
| ~~G0-4~~ | ~~`terraform apply` (creates tunnel + 1P item)~~ | ✅ Done | Tunnel + token in 1Password as `cf_tunnel_home-0ps.com` / `tunnel-token` |
| ~~G0-5~~ | ~~Deploy cluster manifests + verify connectors register, tunnel "Healthy"~~ | ✅ Done 2026-05-25 | Both cloudflared connectors registered; tunnel Healthy in Cloudflare |
| ~~G0-6~~ | ~~Hardening: cloudflared CCNPs~~ | ✅ Done 2026-05-26 | `_lib/security/cilium-network-policies/cloudflared-{default-deny,allow}.yaml`. Egress: kube-dns 53 + world:7844 UDP/TCP + world:443 TCP + gatus.gatus:8080 (tunnel backend). Ingress: host/remote-node + monitoring on :2000 |
| ~~G0-7~~ | ~~Observability: metrics Service + ServiceMonitor~~ | ✅ Done 2026-05-26 | New `cloudflared-metrics` Service + `_lib/observability/kube-prometheus-stack/servicemonitor-cloudflared.yaml`. KPS Prometheus SM selectors are empty (cluster-wide), so no label required |

## Sprint G1 — Deploy Gatus (internal)

**Built with raw manifests** (matches homer/docs-site pattern); image
`ghcr.io/twin/gatus:v5.36.0`, 1 replica, **memory storage** (G1-5 — uptime
history is lost on restart; upgrade path noted below), Recreate rollout.

| ID | Task | Status | Notes |
| -- | ---- | ------ | ----- |
| ~~G1-1~~ | ~~Scaffold `_lib/applications/gatus/{base,overlays/dev}`~~ | ✅ Done | namespace (PSA restricted, policy-target=application), Deployment (RO-rootfs, nonroot 1000), Service, ConfigMap, HTTPRoute, RQ + LimitRange |
| ~~G1-2~~ | ~~Gatus config — endpoint groups~~ | ✅ Done | 5 apps (authentik, grafana, freshrss, homer, docs) probing the live `*.home-0ps.com` hostnames + 2 infra (TrueNAS, UniFi with `insecure: true`). Conditions: `[STATUS] < 400` / `[RESPONSE_TIME] < 3000`. 1P Connect deferred (easy add-on) |
| ~~G1-3~~ | ~~Guardrails — RQ + LimitRange, explicit resources + `runAsUser`~~ | ✅ Done | `runAsUser: 1000` (Kyverno mutation gotcha) |
| ~~G1-4~~ | ~~Hardening: gatus CCNPs~~ | ✅ Done 2026-05-26 | `_lib/security/cilium-network-policies/gatus-{default-deny,allow}.yaml`. Egress: kube-dns 53 + world:443 (covers gateway LB IP + TrueNAS + UniFi probes). Ingress: reserved:ingress (gateway) + host/remote-node + monitoring on :8080 |
| ~~G1-5~~ | ~~Persistence — start memory-only; document upgrade path~~ | ✅ Recorded | `storage.type: memory` for v1. Upgrade path: switch to `sqlite` on a `democratic-csi` PVC (small, cheap) or `postgres` against a new CNPG cluster once S-tier (S-1/S-2 in the lab review) lands |
| ~~G1-6~~ | ~~Top-level Flux Kustomization + `GATUS_SUBDOMAIN` cluster-config var~~ | ✅ Done | `gatus` Kustomization (dependsOn dns/networking/security; mirrors docs-site). Added `GATUS_VERSION` + `GATUS_SUBDOMAIN: dev.int.status` to cluster-configs |
| ~~G1-7~~ | ~~Internal HTTPRoute on the Cilium Gateway~~ | ✅ Done | `dev.int.status.home-0ps.com` → `gatus:8080` via `${GATEWAY_NAME}` (wildcard cert) |
| ~~G1-8~~ | ~~ServiceMonitor: scrape /metrics on :8080~~ | ✅ Done 2026-05-26 | `_lib/observability/kube-prometheus-stack/servicemonitor-gatus.yaml` |
| ~~G1-9~~ | ~~Deploy + verify probes 🟢~~ | ✅ Done 2026-05-25 | 5 apps + 2 infra all green (`docs` endpoint was removed when docs-site retired 2026-05-26) |
| ~~G1-10~~ | ~~Gatus → Slack alerting (was G3-4)~~ | ✅ Done 2026-05-26 | New `gatus-slack-webhook` ExternalSecret (reuses 1Password item `metrics_webhook_dev` → field `credential`). Configmap has `alerting.slack.webhook-url: $${SLACK_WEBHOOK_URL}` (escaped for Flux envsubst) + per-endpoint `alerts: [- type: slack]`. Defaults: 3 failures to fire, 2 successes to resolve, send-on-resolved=true |

## Sprint G2 — Public status board

Public hostname **`dev-status.home-0ps.com`** routed through the Cloudflare
Tunnel from G0; ingress rules + DNS record managed in
`terraform/cloudflare-tunnel/`.

| ID | Task | Status | Notes |
| -- | ---- | ------ | ----- |
| ~~G2-1~~ | ~~Route the Gatus status page through the Cloudflare Tunnel~~ | ✅ Done | Terraform `cloudflare_zero_trust_tunnel_cloudflared_config` (ingress `dev-status.home-0ps.com` → `http://gatus.gatus.svc.cluster.local:8080`) + `cloudflare_dns_record` (CNAME, proxied) |
| ~~G2-2~~ | ~~Harden the public surface — rate limit~~ | ✅ Done 2026-05-26 | `cloudflare_ruleset` (phase `http_ratelimit`, kind `zone`) — **60 req/min per IP** on `dev-status.home-0ps.com`, action `block`, 60s mitigation. WAF managed rules + security headers are a follow-on (O-5 superset). |
| ~~G2-3~~ | ~~Decide public scope~~ | ✅ Done | Full endpoint view (no public/internal split); revisit if topology exposure becomes a concern |

## ~~Sprint G3 — Rebuild the services page (`status.md`)~~ — DROPPED (2026-05-26)

The docs-site (MkDocs wiki) was retired in the same change that delivered G2 —
`_docs/status.md` no longer exists. Gatus is the sole status surface now:
internal at `dev.int.status.home-0ps.com`, public at `dev-status.home-0ps.com`.
Cross-linking to Homer was kept; alerting (originally G3-4) remains a useful
follow-up (Gatus → Slack, or a Prometheus alert on Gatus metrics).

---

## Risks & open questions

- **Cloudflare Tunnel is net-new** — G0 is a genuine prerequisite for the public
  board; scope it carefully (own ADR if it grows).
- **Public exposure scope + hardening** — what's shown publicly, and locking the
  surface down (no admin endpoints, headers, rate limits).
- **Persistence** — memory vs SQLite-on-PVC vs Postgres for uptime history.
- **Endpoint-list ↔ HTTPRoutes drift** — Gatus endpoints are hand-maintained;
  consider deriving from live HTTPRoutes to avoid silent skew when apps are
  added/renamed.

## Acceptance criteria

- Gatus live (internal **and** public), probing all services server-side,
  `/metrics` scraped, uptime history visible.
- Homer tiles the Gatus URL.
- All guardrails met (RQ/LimitRange, CCNP, ServiceMonitor, PSA); Flux all-green.
