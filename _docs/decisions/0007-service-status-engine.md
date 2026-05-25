# ADR-0007: Service status engine — Gatus

- **Status:** **Proposed** (2026-05-25)
- **Date:** 2026-05-25
- **Deciders:** fr3d
- **Related:** [Status page](../status.md) (the page this replaces/feeds), [infra/observability.md](../infra/observability.md) (what's already scrapeable), [service-status sprint](../service-status-sprint.md) (delivery plan).

## Context

The services page ([`status.md`](../status.md)) reports health two ways, both
weak:

- A **browser-side `no-cors` probe** (`assets/js/status.js`) — runs in the
  viewer's browser, so it reflects *the viewer's* reachability (only on-LAN where
  `dev.int.*` resolves), can't read HTTP status, and has no history or uptime %.
- A **hand-maintained Platform table** that drifts — it currently still claims
  Talos `v1.13.0` while the live cluster is `v1.12.8`.

We want server-side health checks of every service, uptime history / %, a real
status page with a machine-readable API to embed in the docs, and a **public**
status board.

## Decision

Deploy **[Gatus](https://github.com/TwiN/gatus)** as a GitOps app and make it the
service status engine.

## Options considered

1. **Gatus** *(chosen)* — config-as-code YAML (fits GitOps; endpoints live in
   git), lightweight Go service, server-side endpoint probing with conditions
   (status, latency), a status page **+ JSON API + Prometheus `/metrics`**,
   uptime history, and Slack/webhook alerting. State is optional (memory,
   SQLite-on-PVC, or Postgres).
2. **Uptime Kuma** — richer built-in UI and more notifiers, but **UI-driven
   config + SQLite state on a PVC**: the config lives outside git, which fights
   the repo's GitOps model. *Rejected.*
3. **No new app (Grafana embed + build-time snapshot)** — embed Grafana panels
   into `status.md` and render the Platform table from Prometheus `up{}` / Flux
   at build time. No standalone or public status board, and it couples the
   status view to the observability stack. *Rejected as primary* — but the
   Grafana-embed idea is **retained** as a complementary enhancement to the docs
   page (see sprint G3).

## Consequences

- New app under `_lib/applications/gatus/` (base + `overlays/dev`) with its own
  **top-level Flux Kustomization** (per the per-app pattern), namespace (PSA
  `restricted`, `policy-target: application`), **RQ + LimitRange** (the H-4
  pattern), explicit container resources, a **ServiceMonitor**, and a **CCNP**
  (default-deny + `reserved:ingress` for the gateway + egress to probed targets
  and DNS).
- **Public exposure needs a Cloudflare Tunnel, which does not exist in this repo
  yet** (today: Tailscale + Cilium Gateway). Standing up `cloudflared` is a
  prerequisite for the public board and is net-new exposure infrastructure
  (sprint G0) — it may warrant its own ADR if it grows.
- **History persistence is a sub-decision:** start memory-only (simplest) or
  SQLite-on-PVC; add Postgres (CNPG) later if durable long-term history matters.
- Gatus's endpoint list becomes a second description of "what services exist" —
  it **overlaps the docs service catalog** (docs-site sprint D2-4). Keep a single
  source of truth; ideally generate one from the other (or from HTTPRoutes).
- `runAsUser` must be set explicitly on the container — the Kyverno
  `add-default-securitycontext` policy otherwise mutates it to 65534.
