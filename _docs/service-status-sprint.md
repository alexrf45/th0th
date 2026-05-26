# Service Status (Gatus) — Sprint Plan

> Created: 2026-05-25. Owner: alexrf45.
> Goal: deploy **Gatus** as the service status engine and rebuild the services
> page ([`status.md`](status.md)) to consume it — server-side health, uptime
> history, and a public status board.
> Decisions locked 2026-05-25 ([ADR-0007](decisions/0007-service-status-engine.md)):
> Gatus; exposed **internal + public** (Cloudflare Tunnel); plan tracked here.

## Why

Today's services page probes from the **viewer's browser** (`status.js`) — on-LAN
only, no HTTP status, no uptime history — and a **hand-maintained Platform table**
that drifts (still says Talos `v1.13.0` vs live `v1.12.8`). The page itself
already proposes Gatus as the fix. This sprint builds it.

## Scope

- **In:** Gatus app (GitOps), internal + public exposure, status.md rebuilt to
  consume Gatus, Homer tile, alerting.
- **Prerequisite (net-new):** a Cloudflare Tunnel — none exists yet (G0).
- **Out:** replacing Grafana/Prometheus (Gatus complements, not replaces them).

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
| G0-4 | Provide the Cloudflare API token + account ID + vault ID, then `terraform apply` (creates tunnel + 1P item) | ⏳ user | Account-scoped Tunnel:Edit token; populate tfvars (SOPS) or `op` inject |
| G0-5 | Deploy cluster manifests + verify: ESO syncs the secret, both connectors register, tunnel "Healthy" | ⏳ | `kube dev -n cloudflared get pods`; Cloudflare shows 2 connectors |
| G0-6 | **Hardening (deferred):** CCNP `cloudflared-default-deny` + `cloudflared-allow` — egress: DNS (kube-dns 53), Cloudflare edge `world` on **7844 UDP+TCP** and **443 TCP**; ingress on 2000 from `host`/`remote-node` (probes) + Prometheus. Deferred so the first connect isn't blocked by a wrong egress rule | ❌ | `_lib/security/cilium-network-policies/cloudflared-*` |
| G0-7 | **Observability (deferred):** metrics `Service` + `ServiceMonitor` scraping `/metrics` on 2000 | ❌ | Confirm the kube-prometheus-stack serviceMonitor selector label |

## Sprint G1 — Deploy Gatus (internal)

| ID | Task | Files | Done when |
| -- | ---- | ----- | --------- |
| G1-1 | Scaffold `_lib/applications/gatus/{base,overlays/dev}` — Deployment/HelmRelease, Service, namespace (PSA restricted + `policy-target: application`), ConfigMap, kustomization | `_lib/applications/gatus/` | Renders via `kube dev kustomize` |
| G1-2 | Gatus config — endpoint groups for every service (authentik, grafana, freshrss, homer, docs) + infra (TrueNAS, UniFi, 1P Connect); conditions (status, response-time), intervals, branding | `gatus` ConfigMap | Verified vs live HTTPRoutes/Services |
| G1-3 | Guardrails — RQ + LimitRange (H-4), explicit resources, explicit `runAsUser`, ServiceMonitor for `/metrics` | base | Pods compliant; metrics scraped |
| G1-4 | CCNP — default-deny + `reserved:ingress` (gateway) + egress to probed in-cluster services, DNS, and external targets (TrueNAS/UniFi/internet) | `_lib/security/cilium-network-policies/gatus-*` | Probes succeed under policy |
| G1-5 | Persistence — start memory-only (or SQLite-on-PVC); document the Postgres/CNPG upgrade path | base / overlay | Decision recorded |
| G1-6 | Top-level Flux Kustomization `gatus` + `GATUS_SUBDOMAIN` cluster-config var | `_clusters/dev/cluster.yaml`, `_clusters/dev/config/cluster-configs.yaml` | Reconciles green |
| G1-7 | Internal HTTPRoute `dev.int.status.home-0ps.com` on the Cilium Gateway (wildcard cert) | base/httproute | Reachable internally |

## Sprint G2 — Public status board (depends on G0)

| ID | Task | Notes |
| -- | ---- | ----- |
| G2-1 | Route the Gatus status page through the Cloudflare Tunnel (e.g. `status.home-0ps.com`) | Depends on G0 |
| G2-2 | Harden the public surface — read-only page, no admin/config endpoints exposed, rate limiting + security headers | Ties to review item **O-5** (gateway hardening) |
| G2-3 | Decide public scope — full internal view vs a public subset of endpoints | Privacy of internal topology |

## Sprint G3 — Rebuild the services page (`status.md`)

| ID | Task | Files | Done when |
| -- | ---- | ----- | --------- |
| G3-1 | Replace the `no-cors` browser probe with a fetch of Gatus's JSON API (`/api/v1/endpoints/statuses`) rendered client-side, or iframe-embed the Gatus page | `_docs/status.md`, `_docs/assets/js/status.js` | Page shows real server-side health + uptime |
| G3-2 | Make the Platform table accurate — embed Grafana panels (allow_embedding) or render at build time from Prometheus `up{}`/Flux; kill stale hand-maintained values | `status.md`, `main.py` (macros) | No stale data (fix Talos version) |
| G3-3 | Cross-link — Homer tile for Gatus; keep Gatus endpoints ↔ docs service catalog (docs-site D2-4) consistent; link status ↔ Gatus ↔ Grafana | `_lib/applications/homer/base/configmap.yaml`, docs | Single source of truth for endpoints |
| G3-4 | Alerting — Gatus → Slack (reuse the Alertmanager Slack pattern) or a Prometheus alert on Gatus metrics | gatus config / observability | Down service pages someone |

---

## Risks & open questions

- **Cloudflare Tunnel is net-new** — G0 is a genuine prerequisite for the public
  board; scope it carefully (own ADR if it grows).
- **Public exposure scope + hardening** — what's shown publicly, and locking the
  surface down (no admin endpoints, headers, rate limits).
- **Persistence** — memory vs SQLite-on-PVC vs Postgres for uptime history.
- **Endpoint-list duplication** — Gatus config vs the docs service catalog
  (D2-4); pick one source of truth, ideally derive from HTTPRoutes.

## Acceptance criteria

- Gatus live (internal + public), probing all services server-side, `/metrics`
  scraped, uptime history visible.
- `status.md` reflects real health (no browser-only probe, no stale Platform
  data); Homer links to it.
- All guardrails met (RQ/LimitRange, CCNP, ServiceMonitor, PSA); `mkdocs build
  --strict` green; Flux all-green.
