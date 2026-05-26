# home-0ps.com Review — 2026-05-26

> Generated: 2026-05-26 (`/lab-review`). Supersedes `home-0ps-review-2026-05-25.md`.
> Scope: Status update against the 2026-05-25 review. Live `memphis` dev cluster surveyed at rev `be95cb9` (HEAD of `dev`).
> Trigger: Service-status sprint shipped end-to-end + docs-site retired. **22 commits since 2026-05-25**; headline = **Gatus is live (internal + public via a brand-new Cloudflare Tunnel)** and **the MkDocs docs-site was spun down in one pass**. Sprint C app guardrails (H-4/P-2/P-3) + the Cilium agent OOM fix (P-4) also landed.

---

## Executive Summary

A productive 30 hours: the **service-status sprint shipped end-to-end** — Gatus deployed internally at `dev.int.status.home-0ps.com` and exposed publicly through a brand-new Terraform-managed Cloudflare Tunnel at `dev-status.home-0ps.com`. Six endpoints all 🟢 (5 apps + TrueNAS + UniFi). The **MkDocs docs-site was retired one-pass** (CryptPad lesson): namespace, Flux Kustomization, CCNPs, build pipeline, CI workflow, wiki-only docs, **and the GHCR image package** all removed.

Along the way: **Sprint C app guardrails landed** (H-4 RQ+LimitRange backfill to authentik + homer; P-2 explicit authentik resources; P-3 Kyverno admission HA), and the **Cilium agent OOMKill (P-4) was fixed** mid-rollout — memory limit `250Mi → 768Mi`, terraform parity at `cilium_config.tf:18`.

Live state is healthy: **6 nodes Ready** (Talos `v1.12.8` / k8s `v1.35.0`, ~30h), **16 Flux Kustomizations + flux-system, all True@be95cb9**, **all 16 HelmReleases Ready**, no pods outside Running/Completed, 3 certs Ready (wildcard on `letsencrypt-production`; barman-cloud certs pruned with the plugin), both CNPG clusters 3/3 healthy.

**Headline changes since 2026-05-25:**

- **Service-status stack live (G0 → G1 → G2):**
  - **G0** — Cloudflare Tunnel: net-new exposure infra. New Terraform root `terraform/cloudflare-tunnel/` (own S3 state) creates the tunnel + writes the connector token to 1Password (`cf_tunnel_home-0ps.com`); ESO syncs it; **cloudflared `2026.5.1`** runs in `_lib/networking/cloudflared/` (2 replicas, soft anti-affinity, RO-rootfs, nonroot 65532).
  - **G1** — **Gatus `5.36.0`** at `_lib/applications/gatus/` (raw manifests, memory storage, Recreate strategy). Internal HTTPRoute on the Cilium Gateway; new top-level Flux Kustomization mirroring docs-site's `dependsOn`.
  - **G2** — Public ingress + DNS via Terraform (`cloudflare_zero_trust_tunnel_cloudflared_config` + `cloudflare_dns_record`, proxied=true). Homer gets a Gatus tile.
- **docs-site retired (2026-05-26):** Flux pruned the Kustomization → all docs-site resources gone. Build pipeline (`mkdocs.yml`, `main.py`, `requirements-docs.txt`, `docs-site/Dockerfile`), CI workflow (`.github/workflows/docs-site.yml`), wiki-only docs (`_docs/status.md`, `_docs/assets/js/status.js`, `_docs/roadmap.md`), and the **GHCR image package** all deleted. `_docs/` markdown content kept as engineering reference. Sprint G3 dropped; the superseded `docs-site-wiki-revamp-sprint.md` archived.
- **Sprint C guardrails** (`f9bef38`, `04ca94c`): H-4 (RQ + LimitRange on authentik, homer; freshrss already had them), P-2 (authentik server `req 640Mi/lim 1Gi`, worker `req 512Mi/lim 1Gi`), P-3 (Kyverno admission `replicas: 2`), P-4 (Cilium agent `req 384Mi / limit 768Mi`).
- **Sprint D1 (wiki revamp foundation)** shipped *before* the spin-down (mermaid wiring, reference-first nav, journey archive, Home landing page). D2–D4 are now superseded.

**Known gap (still the headline open item):** **Zero DB backups.** No progress on the storage S-tier this cycle. Same gap as the last two reviews.

**Recommended next sprint:** **Storage S-tier (S-1 → S-2)** — backups remain the biggest exposure and this is the third cycle they've slipped. **Service-status hardening** (CCNPs + ServiceMonitors + public-surface rate-limits) is a smaller, contained alternative that builds directly on this cycle's wins. **H-3 Falco** is still the obvious security-tier pickup. See §5.

---

## Section 1 — What Changed Since 2026-05-25

| Area | 2026-05-25 state | 2026-05-26 state |
| ---- | ---------------- | ---------------- |
| Cluster lifecycle | Rebuilt ~6h, healthy | Healthy, ~30h (no rebuild) |
| Service status engine | ❌ None | ✅ **Gatus `5.36.0` live** — internal + public |
| Cloudflare Tunnel | ❌ None (Tailscale + Cilium Gateway only) | ✅ **Stood up** — Terraform-managed, cloudflared `2026.5.1` (2 replicas, HA) |
| Public exposure | ❌ Internal-only | ✅ `dev-status.home-0ps.com` (Gatus). Phase-4 prereq met. |
| docs-site (MkDocs wiki) | ✅ Live (`dev.int.docs`) | 🗑️ **Retired** — one-pass spin-down; GHCR image deleted |
| H-4 RQ + LimitRange | 🟡 Partial → ✅ Done | ✅ Done — now also covers gatus + cloudflared |
| P-2 authentik resources | ❌ Missing → ✅ Done | ✅ Done (`f9bef38`) |
| P-3 Kyverno admission HA | ❌ Single-replica → ✅ Done | ✅ Done (`f9bef38`) — `replicas: 2` |
| P-4 Cilium agent OOM | (new finding) | ✅ Done (`04ca94c`) — `req 384Mi / limit 768Mi` |
| Homer tile content (HM-2) | ❓ Unverified | ✅ Verified + Gatus tile added |
| Wiki revamp (D1) | ❌ Not started | ✅ D1 shipped pre-spin-down; D2–D4 superseded |
| Flux DAG | 17 Kustomizations | **16** in `cluster.yaml` (`+gatus`, `-docs-site`) + `flux-system` |
| Certs | 5 (incl. barman-cloud-*) | 3 — barman-cloud certs pruned ✅ |

---

## Section 2 — Live Cluster Snapshot (2026-05-26, rev `be95cb9`)

```
Nodes:        6 Ready — 3 cp + 3 worker — Talos v1.12.8 / k8s v1.35.0 — ~30h
Flux:         16 Kustomizations + flux-system — ALL True@be95cb9
              (cluster-config, coredns, crds, controllers, pki, external-secrets-operator,
               secrets, networking, dns, storage, observability, security,
               freshrss, authentik, homer, gatus)
HelmReleases: 16, all Ready (Flux v2.8.8; cnpg 0.27.0 + cnpg-crds 1.28.0; kps 78.0.0;
              authentik 2026.2.3; kyverno 3.7.0 [admission replicas: 2]; cert-manager v1.19.3)
Certs:        wildcard-tls (letsencrypt-PRODUCTION), trust-manager, op-connect-tls — all Ready.
              barman-cloud-{client,server}-tls pruned with the plugin (hygiene win).
Workloads:    no pods outside Running/Completed.
gatus:        1 pod Running — probing 6 endpoints (5 apps + TrueNAS + UniFi), all 🟢.
cloudflared:  2 pods Running (53m+) — tunnel Healthy in Cloudflare; routes dev-status.
freshrss:     app 1/1 + CNPG 3/3. RQ + LimitRange + PDBs live.
authentik:    server 1/1 (req 640Mi/lim 1Gi) + worker 1/1 (req 512Mi/lim 1Gi) + CNPG 3/3.
              RQ + LimitRange now live (H-4).
CNPG:         authentik-dev-cluster 3/3 + freshrss-dev-cluster 3/3, both "healthy".
              Still no backups: plugins={} backup={} — 0 ObjectStores, 0 ScheduledBackups (S-5).
PVCs:         all CNPG data+WAL on local-path; freshrss app + prometheus/grafana/alertmanager on iscsi.
              No docs-site PVCs (stateless app — clean retirement).
```

Notable:

- **Service-status story shipped end-to-end in one work session.** Gatus is the single source of service health now; the browser-probe approach in the old docs-site is gone.
- **Cloudflare Tunnel is net-new exposure infra** — it also unlocks Phase 4 (SSO public exposure). A dedicated ADR is likely warranted if it grows beyond Gatus.
- **No DB backups.** Same state as 2026-05-22 and 2026-05-25. Third review unchanged.
- **Talos still pinned to v1.12.8** (I-1) — no change.
- **Kyverno admission is HA** — pod admission no longer has a SPOF on the mutating-webhook path.

---

## Section 3 — Open Items Punch List

Grouped by tier. Each item: **ID · what · status · location · next action.**

### CRITICAL — correctness / data integrity

(No open CRITICAL items. The total absence of DB backups is tracked as **S-5/S-1** below — accepted in dev only until the storage sprint.)

### HIGH — security hardening

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| H-2 | Cilium NetworkPolicies — `world:443` egress tightening | ⚠️ Open | `_lib/security/cilium-network-policies/` | Tighten to `toFQDNs` once L7 DNS policy is on. |
| H-3 | **Falco** | ❌ Disabled — **top security item** | `_lib/controllers/kustomization.yaml`, `_lib/security/kustomization.yaml` | HR wired; `falco-rules/` empty stub. Decide CRD-ownership (Q1; `crds`-layer precedent exists). Uncomment both, verify `modern_ebpf` on Talos + ServiceMonitor scrape. |
| ~~H-4~~ | ~~ResourceQuotas + LimitRanges~~ | ✅ Done (`f9bef38`) | now also covers gatus + cloudflared | — |
| H-5 | Trivy operator | ❌ Empty dir | `_lib/security/trivy/`, `_lib/security/kustomization.yaml` | Populate HR, wire reports → Prometheus/Grafana. Deprioritized below Falco. |
| N-1 | **cloudflared egress CCNP** (deferred G0-6) | ⚠️ Open | `_lib/security/cilium-network-policies/cloudflared-*` (TBD) | Rules: DNS (kube-dns 53), Cloudflare edge `world` on **7844 UDP+TCP** and **443 TCP**; ingress on 2000 from host/remote-node + Prometheus. Deferred so a wrong rule wouldn't block first connect. |
| N-2 | **gatus egress CCNP** (deferred G1-4) | ⚠️ Open | `_lib/security/cilium-network-policies/gatus-*` (TBD) | Egress to in-cluster app services + DNS + external probe targets (TrueNAS 192.168.20.106, UniFi 10.3.3.1). Ingress from gateway (`reserved:ingress`) + Prometheus on 8080. |
| O-5 | Cilium Gateway hardening + **G2-2 public-surface hardening** | ❌ | exposed HTTPRoutes (authentik/freshrss/grafana/homer/gatus) + public `dev-status.home-0ps.com` | Strip `Server`/`X-Powered-By`, body-size limits, rate limits. **Public**: Cloudflare WAF + rate-limit rules on the tunnel ingress. |

### Performance / capacity

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~P-1~~ | ~~apiserver scrape cardinality~~ | ✅ Done (`be19e56`) | — |
| ~~P-2~~ | ~~authentik server/worker resources missing~~ | ✅ Done (`f9bef38`) | — |
| ~~P-3~~ | ~~Kyverno admission SPOF~~ | ✅ Done (`f9bef38`) | `replicas: 2` |
| ~~P-4~~ | ~~Cilium agent OOMKilled (250Mi too low)~~ | ✅ Done (`04ca94c`) | req `384Mi` / limit `768Mi`; terraform parity at `cilium_config.tf` |

### MEDIUM — resilience

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~R-1~~ | ~~PodDisruptionBudgets~~ | ✅ Done | freshrss + CNPG PDBs live. (gatus single-replica; cloudflared 2-rep but no PDB yet — optional.) |
| R-3 | HPA | ⏸️ Deferred | Stateful single-replica apps; no candidate. |
| ~~R-7~~ | ~~`terminationGracePeriodSeconds`~~ | ✅ Done freshrss | Optional: authentik server/worker. |
| ~~R-8~~ | ~~Authentik CNPG archiving erroring~~ | ✅ Resolved | Superseded by S-5: no backups for *either* cluster. |
| N-6 | **Gatus persistence upgrade path** (G1-5) | ⏸️ Memory-only for v1 | `_lib/applications/gatus/base/configmap.yaml` (`storage.type: memory`) | Switch to `sqlite` on a small `democratic-csi` PVC, or `postgres` against a new CNPG cluster once S-tier lands. History lost on restart today. |

### Observability follow-ups

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~O-4~~ | ~~K8s events → Loki~~ | ✅ Done | — |
| O-5 | Gateway + public-surface hardening | ❌ | (see HIGH tier above) |
| O-6 | Periodic posture scans | ❌ | `popeye` + `kubescape` CronJobs → Loki. |
| ~~O-7~~ | ~~Alertmanager routing~~ | ✅ Done | Follow-up app rules: cert expiry, PVC near-full, CNPG no-backup/snapshot-age once S-2 lands, **Gatus endpoint-down via metrics** once N-3 lands. |
| O-8 | Default-deny CCNP (cluster-wide fail-closed) | 🟡 Per-app default-deny landed | Add a cluster-wide default-deny for unlabeled namespaces (Q4). |
| O-9 | App-level dashboards/alerts | ❌ | Flip Authentik `serviceMonitor.enabled: true`; add freshrss/authentik dashboards. |
| N-3 | **ServiceMonitors for gatus + cloudflared** (deferred G0-7, G1-8) | ⚠️ Open | `_lib/applications/gatus/base/`, `_lib/networking/cloudflared/` (TBD) | Confirm the kube-prometheus-stack SM selector label, add SM + matching Service (gatus on `:8080`, cloudflared metrics on `:2000`). |
| N-5 | **Gatus alerting → Slack** (orphaned G3-4) | ❌ | `_lib/applications/gatus/base/configmap.yaml` (Gatus `alerting:` block) or a Prometheus alert on Gatus metrics once N-3 lands | Reuse the Alertmanager Slack pattern. |

### Homer follow-ups

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| HM-1 | Homer read-only root FS | ⚠️ `readOnlyRootFilesystem: false` | `_lib/applications/homer/base/deployment.yaml` | Enumerate writable paths, mount `emptyDir`, flip to RO. |
| ~~HM-2~~ | ~~Homer service-tile content~~ | ✅ Done — Gatus tile added; docs-site never tiled | `_lib/applications/homer/base/configmap.yaml` | Tile list now: FreshRSS, Authentik, Grafana, Gatus, TrueNAS, UniFi. |
| ~~DS-1~~ | ~~docs-site living-scaffold pages manual~~ | 🗑️ N/A — docs-site retired | — | — |

### Storage migration (S-tier — STILL backup-critical, **no progress this cycle**)

> Strategy decided 2026-05-25: **local TrueNAS zvol snapshots** (ADR-0003). barman-cloud removed.

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| S-1 | Snapshot infrastructure | ❌ Absent | `global/crds/`, `_lib/storage/freenas-csi/` | Add external-snapshotter CRDs + snapshot-controller, enable democratic-csi snapshotter sidecar, create `VolumeSnapshotClass`. Verify a manual snapshot. **Blocks S-2.** |
| S-2 | CNPG → static iSCSI zvol + scheduled snapshots | ❌ Not started | `_lib/applications/{authentik,freshrss}/overlays/dev/database.yaml` | Pre-create zvols + static `Retain` PVs; CNPG `instances:1`; static `pvcTemplate.volumeName`; `ScheduledBackup` of method `volumeSnapshot`. Verify operator `0.27.0` honors `volumeName` on a throwaway cluster first (Q2). |
| ~~S-3~~ | ~~Retire R2/S3 from CNPG path~~ | ✅ Done — barman-cloud plugin gone | — | — |
| S-4 | iscsi StorageClass reclaim default | ⚠️ `Delete` | `_clusters/dev/config/cluster-configs.yaml` (`RECLAIM_POLICY`) | Flip to `Retain`. |
| S-5 | **No CNPG backups (both clusters)** | ⚠️ **Real gap** — 3rd review unchanged | `_lib/applications/{authentik,freshrss}/overlays/dev/database.yaml` | Resolved by S-1 → S-2. Zero DB recovery capability today. |

### Hygiene / cleanup

| Item | Location | Action |
| ---- | -------- | ------ |
| ~~barman-cloud certs~~ | `database/barman-cloud-{client,server}-tls` | ✅ Pruned with the plugin. |
| ~~docs-site GHCR image package~~ | `ghcr.io/alexrf45/home-0ps-docs` | ✅ Deleted via `gh api -X DELETE /user/packages/container/home-0ps-docs`. |
| ~~Sprint D1 superseded plan~~ | `_docs/docs-site-wiki-revamp-sprint.md` | ✅ Archived to `_docs/archive/`. |
| ~~docs-site wiki-only files~~ | `_docs/status.md`, `_docs/assets/js/status.js`, `_docs/roadmap.md` | ✅ Removed. |
| CryptPad TrueNAS zvol | `dev-cryptpad-data-pvc` | ❓ **Still unverified** — confirm destroyed. |
| Placeholder cluster | `_clusters/production/` | Leave until prod promotion. |

### Terraform / IaC

| ID | Item | Status | Note |
| -- | ---- | ------ | ---- |
| ~~TF-CoreDNS~~ | ~~Apply CoreDNS split-horizon inlineManifest~~ | ✅ Superseded — Flux-owned `coredns` | — |
| ~~ADR-0006~~ | talos-pve module refactor + provider upgrades | ✅ Done | — |
| ~~TF-CFTunnel~~ | **New: Cloudflare Tunnel TF root** | ✅ **Done (G0)** | `terraform/cloudflare-tunnel/` (own S3 state). API token account-scoped: Tunnel:Edit + Zone:DNS:Edit. |
| I-1 | Talos `kubernetes_version` pinned to v1.12.8 | ⚠️ Open | `terraform/dev/` (`fc20340`). Revisit unpin when upstream supports 1.36.0 cleanly. |
| Sprint 6 | Node-label apply-ordering (`kubernetes_labels.worker_role` fails first apply) | ⏸️ Deferred (ADR-0006 #15) | Retry-on-apply workaround stands. |
| R1 | Collapse `pve.tf` cp/worker duplication | 🟡 Verify post-refactor | Confirm within-module collapse (must not break node scaling). |
| R2 | Extract shared Talos machine config | 🟡 Verify post-refactor | Confirm worker CP-only PSA exemptions. |
| R5 | Worker memory typo `8092` | ⚠️ Open | `terraform/dev/variables.tf` + `terraform.tfvars` — tidy on next tfvars edit. |

### Manual / non-GitOps

| Item | Status | Note |
| ---- | ------ | ---- |
| Beelink S13 BIOS power-loss = "Power On" | ❓ Unverified | Pairs with Proxmox HA for power-blip recovery. |
| system-upgrade-controller for Talos | ⏸️ Hack-only | `_hack/scripts/upgrade.sh`; not in Flux. |
| SSO public exposure (Phase 4) | ⏸️ **Unblocked** | Cloudflare Tunnel now exists (G0); forward-auth outposts + WAF terraform still not built. The infra prereq is met. |

---

## Section 4 — Thoth & future apps — Status

**Thoth** — ✅ Descoped (ADR-0005). No change.

**docs-site** — 🗑️ **Retired (2026-05-26)**. MkDocs wiki spun down one-pass. `_docs/` markdown retained as engineering reference. Sprint D1 foundation shipped pre-spin-down (mermaid wiring, nav reorg, journey archive, Home revamp); D2–D4 superseded.

**Gatus** — ✅ **Live (G0+G1+G2)**. Internal `dev.int.status.home-0ps.com`, public `dev-status.home-0ps.com`. 6 endpoints all 🟢. Memory-only persistence (N-6 upgrade path).

**Cloudflare Tunnel** — ✅ **Live (G0)**. Net-new exposure infra. May warrant its own ADR if it grows beyond Gatus.

**GPU sharing** — pre-decision (ADR-0004) unchanged. Deferred to a future Talos-PVE module rev.

---

## Section 5 — Suggested Next Sprint

In order, cut at natural stopping points:

1. **Storage S-tier — S-1 → S-2** (third cycle as recommended #1; backups are absent today). external-snapshotter + snapshot-controller + `VolumeSnapshotClass` (S-1), verify a manual snapshot, then convert one CNPG cluster to static zvol PV + `ScheduledBackup`/volumeSnapshot (S-2). Add the O-7 "no-backup / snapshot-age" alert alongside.
2. **Service-status hardening** (small, contained, builds on this cycle's wins): **N-1** cloudflared CCNP + **N-2** gatus CCNP — egress rules already documented in sprint G0-6/G1-4. Add **N-3** ServiceMonitors. Then **G2-2 / O-5 public-surface hardening** — Cloudflare WAF + rate limits on `dev-status.home-0ps.com`.
3. **H-3 Falco** — long-standing top security item. CRD-ownership precedent now exists.
4. **S-4 + I-1 + TF verify** — flip iscsi reclaim to `Retain`; revisit the Talos v1.12.8 pin; verify R1/R2 module collapse.
5. **O-5 / O-6 / O-9 / N-5** — gateway hardening + posture scans + app dashboards + Gatus alerting to Slack.

---

## Section 6 — Files Referenced

| File | Why it matters |
| ---- | -------------- |
| `terraform/cloudflare-tunnel/` | G0 — new TF root; own S3 state; tunnel + token data source + 1P item + G2 ingress + DNS record |
| `_lib/networking/cloudflared/` | G0 — in-cluster connector (2 replicas, token via ESO from `cf_tunnel_home-0ps.com`) |
| `_lib/applications/gatus/` | G1 — status engine (memory storage; 6 endpoints; HTTPRoute via Cilium Gateway) |
| `_clusters/dev/cluster.yaml` | Flux DAG — `+gatus`, `-docs-site` |
| `_clusters/dev/config/cluster-configs.yaml` | `+GATUS_VERSION`, `+GATUS_SUBDOMAIN`; `-DOCS_SUBDOMAIN` |
| `_lib/applications/homer/base/configmap.yaml` | Gatus tile added (HM-2 closed) |
| `_lib/security/cilium-network-policies/kustomization.yaml` | `-docs-site-*` CCNPs; no gatus/cloudflared CCNPs yet (N-1/N-2) |
| `_lib/controllers/kyverno/helmrelease.yaml` | P-3 — `admissionController.replicas: 2` |
| `_lib/controllers/authentik/helmrelease.yaml` | P-2 — explicit server + worker resources |
| `terraform/modules/talos-pve-v3.1.0/cilium_config.tf` | P-4 terraform parity (Cilium 768Mi limit) |
| `_docs/decisions/0007-service-status-engine.md` | ADR (Proposed) — service status engine = Gatus |
| `_docs/service-status-sprint.md` | G0/G1/G2 punch list (G3 dropped) |
| `_docs/archive/docs-site-wiki-revamp-sprint.md` | Superseded plan (docs-site retired) |
| `_docs/reviews/home-0ps-review-2026-05-25.md` | Prior review — superseded |
