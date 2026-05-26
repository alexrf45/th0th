# docs-site Wiki Revamp — Sprint Plan

> Created: 2026-05-25. Owner: alexrf45.
> Goal: pivot docs-site from a narrative ("how the lab came to be") into an
> **architecture / network reference wiki** — a pane of glass for the running
> state of the lab, organized by layer, with diagrams and reference tables.
> Decisions locked 2026-05-25: archive `journey.md`; full reorg + diagrams + new
> reference artifacts; **mermaid in-markdown**; plan tracked in this doc.

## Scope & non-goals

**In scope:** information architecture (nav) reorg, mermaid diagrams, and new
network/architecture reference pages + tables. Content is the work — the build
pipeline stays as-is.

**Out of scope / unchanged:** the build pipeline (`mkdocs.yml` → CI
`.github/workflows/docs-site.yml` → `ghcr.io/alexrf45/home-0ps-docs` →
digest-pinned nginx Deployment), the k8s manifests at
`_lib/applications/docs-site/`, and the `macros` roadmap-injection system. The
only `mkdocs.yml` edits are the mermaid fence + the new `nav:` tree.

**Guiding rule:** every reference page must be **factual** — cross-checked
against the live cluster (via the `kube`/`k8sop` wrappers) and the manifests in
`_lib/`, never invented. Treat unverified values (CIDRs, VLAN IDs) as TODOs to
confirm, not guesses. See `.claude/rules/code.md`.

---

## Current state (audit 2026-05-25)

- **Stack:** Material for MkDocs 9.7.6, built from `_docs/` (30 MD files),
  `mkdocs build --strict` in CI. Theme + search + macros already configured.
- **Nav today** mixes narrative and reference: Home, **Journey**, Apps (3),
  Infrastructure (5: storage/observability/networking/dns/secrets-pki), Best
  Practices, Decisions (6 ADRs), Roadmap, Status, Reviews.
- **No diagrams exist.** `pymdownx.superfences` is present but no mermaid fence
  is configured and no diagram syntax is used anywhere.
- **`journey.md`** (82 lines) is the narrative to archive.
- **`infra/networking.md` + `dns.md`** are the seeds of the network reference;
  hardware facts live in `.claude/rules/lab_architecture.md`.

---

## Target information architecture

Reference-first, layered to mirror the physical → logical → platform → app stack
(and the Flux reconciliation order). Proposed `nav:`:

- **Home** — what the lab is (1 paragraph) + system-context diagram + jump-index
- **Architecture**
  - Overview (system context: Git → Flux → cluster; secrets flow)
  - Hardware / Physical (inventory + host diagram)
  - Cluster topology (Talos cp/worker, Proxmox placement, node roles)
  - GitOps & reconciliation flow (Flux layer DAG)
- **Network** ← the core of this revamp
  - Topology (physical + logical diagram)
  - Addressing (VLAN / subnet / CIDR + node IP table)
  - DNS (split-horizon, CoreDNS forward) — from `dns.md` + diagram
  - Ingress & external exposure (Cilium Gateway, Tailscale, Cloudflare, Ngrok; cert flow; request-path diagram)
  - Egress & NetworkPolicy matrix (CCNPs per app)
  - Service catalog (app → ns → hostname → exposure → port → backing DB)
- **Infrastructure** — storage, observability, secrets & PKI (existing pages + diagrams)
- **Platform & Security** — Kyverno policies, PSA per namespace (Falco/Trivy placeholders → H-3/H-5)
- **Applications** — authentik, freshrss, homer (standardized reference template)
- **Decisions** — ADRs (unchanged)
- **Operations** — best-practices, status, roadmap, reviews
- *(Archive: `journey.md` — `_docs/archive/`, `not_in_nav`)*

---

## Sprints

Effort is rough; cut at natural stopping points. Each sprint ends with a green
`mkdocs build --strict` (the existing CI gate).

### Sprint D1 — Foundation & IA (½–1 day)

| ID | Task | Files | Done when |
| -- | ---- | ----- | --------- |
| D1-1 | Wire mermaid into MkDocs (superfences `custom_fences` for `mermaid`; Material auto-loads mermaid.js) | `mkdocs.yml` | A test ```mermaid block renders; `--strict` green |
| D1-2 | Define the new reference-first `nav:` taxonomy (sections above) | `mkdocs.yml` | Nav reflects layered structure |
| D1-3 | Archive `journey.md` → `_docs/archive/journey.md`; drop from nav; fix inbound links | `_docs/journey.md`, `README.md`, any refs | No broken links (`--strict`) |
| D1-4 | Rewrite Home (`README.md`) as a wiki landing: 1-para "what this is" + system-context diagram + grid-card jump index | `_docs/README.md` | Home is reference, not story |

### Sprint D2 — Network reference (1–2 days) — the headline

| ID | Task | Source of truth | Done when |
| -- | ---- | --------------- | --------- |
| D2-1 | `network/topology.md` — physical + logical mermaid diagram (UniFi GW → 16-port switch → 6× Beelink S13 + Zimaboard NAS `.106` + HP Slim `anubis .87`; Proxmox cluster → Talos VMs → Cilium overlay) | `lab_architecture.md`, `terraform/` | Diagram renders, matches hardware |
| D2-2 | `network/addressing.md` — VLAN/subnet table + node IP table + pod/service CIDRs | **verify** vs cluster (`kube dev get nodes -o wide`, Cilium config) + terraform | Table is accurate (no guessed CIDRs) |
| D2-3 | `network/ingress.md` — Cilium Gateway, internal `*.home-0ps.com`, Tailscale/Cloudflare/Ngrok, cert flow (LE DNS-01 + internal CA); request-path diagram | `_lib/networking/`, HTTPRoutes | All exposure paths documented |
| D2-4 | `network/service-catalog.md` — table: app → namespace → hostname → exposure → port → DB | HTTPRoutes + Services (`kube dev get httproute,svc -A`) | Every exposed service listed |
| D2-5 | `network/policy-matrix.md` — CCNP default-deny + allow summary per app | `_lib/security/cilium-network-policies/` | Matrix matches live CCNPs |
| D2-6 | Enhance `dns.md` with split-horizon diagram (CoreDNS `home-0ps.com` → UniFi `10.3.3.1`) | `_lib/coredns/`, `dns.md` | Diagram + accurate |

### Sprint D3 — Architecture & infra diagrams (1 day)

| ID | Task | Source of truth | Done when |
| -- | ---- | --------------- | --------- |
| D3-1 | `architecture/overview.md` — system context + secrets flow (1P → Connect → ESO; SOPS/Age) diagram | `flux.md`, `_lib/secrets/`, `_lib/external-secrets/` | Renders, accurate |
| D3-2 | `architecture/cluster-topology.md` — Talos cp/worker, Proxmox placement, node labels/roles | `kube dev get nodes`, `terraform/` | Matches live 6-node layout |
| D3-3 | `architecture/gitops-flow.md` — Flux reconciliation DAG (the layered Kustomizations) | `_clusters/dev/cluster.yaml`, `flux.md` | DAG diagram matches layers |
| D3-4 | Add diagrams to `infra/{storage,observability,secrets-pki}.md` (CNPG+iSCSI+snapshots; metrics/logs/traces pipeline; CA + trust-manager) | existing pages + `_lib/` | Each infra page has a diagram |

### Sprint D4 — Apps, platform/security, polish (½–1 day)

| ID | Task | Files | Done when |
| -- | ---- | ----- | --------- |
| D4-1 | Standardize app pages to a reference template (purpose, ns, image/chart, deps, exposure, data/backup, SSO) | `_docs/apps/*.md` | All 3 consistent |
| D4-2 | `platform/security.md` — Kyverno ClusterPolicies + mutations, PSA per namespace; Falco/Trivy placeholders | `_lib/security/kyverno-policies/`, ns labels | Reflects live policy set |
| D4-3 | Cross-linking + `--strict` link audit; ADRs ↔ reference pages "related" links | all | No broken links/anchors |
| D4-4 | Visual polish — grid cards on Home, consistent admonitions, optional glossary | `_docs/`, `mkdocs.yml` | Cohesive look |
| ~~D4-5~~ | ~~Revamp the Home system-context diagram~~ | ✅ **Done** 2026-05-25 | TB layout + grouped subgraphs (Source / Secrets / Cluster) + `classDef` layer colors aligned to the Material palette; `--strict` green. |

---

## Diagram inventory (mermaid)

System context · physical network topology · logical/CIDR overlay · cluster
topology · Flux reconciliation DAG · ingress request path · secrets flow ·
observability pipeline · storage/backup flow · DNS split-horizon.

## mkdocs.yml changes (D1-1)

Add the mermaid custom fence (Material loads `mermaid.js` automatically — no
`requirements-docs.txt` change):

```yaml
markdown_extensions:
  - pymdownx.superfences:
      custom_fences:
        - name: mermaid
          class: mermaid
          format: !!python/name:pymdownx.superfences.fence_code_format
```

Plus the restructured `nav:` (D1-2).

---

## Acceptance criteria

- `mkdocs build --strict` green at every sprint boundary (CI already enforces).
- Nav is reference-first; `journey.md` archived and out of nav.
- Network section has topology + addressing + ingress + service catalog + policy
  matrix, each cross-checked against the live cluster / manifests.
- ≥1 diagram per architecture & infra page.
- macros roadmap injection still works; Renovate digest-pin flow untouched.

## Risks & open questions

- **Verify, don't guess:** exact VLAN IDs, service CIDR, and any static IPs must
  be confirmed against terraform / the live cluster before publishing.
- **Reviews in-nav?** Decide whether dated `reviews/` stay under Operations or
  get trimmed to "latest only" with older ones archived.
- **Exposure of internal topology:** the site is internal-only (`*.home-0ps.com`),
  but confirm comfort with documenting addressing/topology there.
- **Supersedes DS-1** (review open item: "docs-site living-scaffold pages
  manual") and feeds the **O-5** ingress-hardening reference.
```
