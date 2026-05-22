# home-0ps.com Review — 2026-05-22

> Generated: 2026-05-22 (`/lab-review`) — supersedes `home-0ps-review-2026-05-20.md`
> Scope: Status update against `home-0ps-review-2026-05-20.md`, plus `storage-strategy-decision.md` and the restructured docs tree (`_docs/{decisions,guides,journey,reviews}`). Live `memphis` dev cluster surveyed.
> Trigger: Periodic review. 6 commits since 2026-05-20; headline = **MkDocs docs-site shipped as a Flux app**, **R2/object-storage terraform decommissioned**, and an **observability trim** (Tempo removed, k8s events → Loki, Grafana SSO-only). **Known gap (not an incident):** Authentik CNPG WAL archiving now errors because the R2 bucket was decommissioned (2026-05-21) ahead of the storage sprint — acceptable in dev (no backup capability established yet). Interim fix is removing the dead barman-cloud config to stop the error churn; real backup arrives with the S-tier sprint.

---

## Executive Summary

The lab is workload-healthy — 6 nodes Ready (Talos `v1.13.0`, k8s `v1.35.0`, 24d), all HelmReleases Ready, no pods outside Running/Completed, all 5 certs Ready (wildcard on `letsencrypt-production`). At survey time the Flux Kustomization layer was mid-reconcile after the `8735a38` push (transient dependency-wave cascade; `cluster-config`/`controllers`/`crds`/`pki`/`flux-system` already green at the new revision).

**Headline changes since 2026-05-20:**

- **docs-site (MkDocs) is live** — new Flux Kustomization + app (`_lib/applications/docs-site/`), internal `dev.int.docs.home-0ps.com`, `nginx-unprivileged`, image `ghcr.io/alexrf45/home-0ps-docs` pinned to digest (Renovate-tracked), CCNPs mirroring homer. Flux app count 15 → 16.
- **Object-storage terraform decommissioned** (`eb3faf0`) — deleted `terraform/modules/object-storage/`, `terraform/dev/authentik-object-storage/`, and `terraform/dev/wallabag-s3-backup/`; consolidated the Talos module under `terraform/modules/talos-pve-v3.1.0/`. The Authentik R2 bucket was destroyed by the user 2026-05-21.
- **Observability trim** (`8735a38`, today) — **Tempo removed** (app-level tracing not needed): HelmRelease + kustomization entry + Grafana Tempo datasource gone. **O-4 closed** — Alloy now ships k8s events to Loki (`loki.source.kubernetes_events`, verified the `alloy` ClusterRole grants `events {get,list,watch}`). **Grafana SSO-only** — local login form hidden; `grafana-admin` secret retained for break-glass.

**Known, accepted gap — Authentik CNPG archiving erroring (R-8).** `kube dev -n authentik get cluster` → `ContinuousArchiving=False` (`barman-cloud-wal-archive: exit status 4`), `LastBackupSucceeded=False`, last failure `2026-05-22T00:00:09Z`. Expected: R2 was decommissioned (2026-05-21) ahead of the storage sprint, but the Authentik manifests (`ob-archiver.enc.yaml`, the `barman-cloud` plugin in `database.yaml`, the `authentik-r2-creds` ExternalSecret) still target it. **This is dev — an unprotected DB is acceptable; backup capability is intentionally deferred to the S-tier sprint.** The only live concern is the recurring `archive_command` failure: unarchived WAL accumulates on the 2Gi WAL PVC and can eventually fill it. Cheap interim fix is removing the dead R2 barman-cloud config (≠ establishing backup).

**Still open and not moving:** the security-hardening tier — Falco (H-3), ResourceQuotas/LimitRanges (H-4, grep confirms NONE), Trivy (H-5). Resilience gaps persist: zero PodDisruptionBudgets (R-1, NONE), no `terminationGracePeriodSeconds` (R-7). Storage migration S-tier (S-1…S-5) still not started — it's where the real backup capability (deferred by R-8) will land.

**Recommended next sprint:** **freshrss resilience bundle (H-4 + R-1 + R-7)**, then **Falco (H-3, the evaluated next security tool)**. Quick interim hygiene: strip the dead Authentik R2 barman-cloud config (R-8) to stop archiving errors. Real backup capability is the storage S-tier sprint, on its own track. See §5.

---

## Section 1 — What Changed Since 2026-05-20

| Area | 2026-05-20 state | 2026-05-22 state |
| ---- | ---------------- | ---------------- |
| Docs site | ❌ None (just the `_docs/` tree) | ✅ **docs-site live** — MkDocs Material → `nginx-unprivileged`, own Flux Kustomization (`docs-site`), internal `dev.int.docs.home-0ps.com`, image pinned to digest, CCNPs mirror homer (`50b62a4`/`1596964`/`b29733a`/`3744bae`). |
| Tracing (Tempo) | ✅ Tempo deployed (30Gi iscsi, OTLP) | ✅ **Removed** (`8735a38`) — HR + kustomization + Grafana datasource gone. PVC `storage-tempo-0` (30Gi) pending manual delete after prune. |
| Logs / events (Alloy) | Logs-only; events not shipped (O-4 open) | ✅ **k8s events → Loki** (`8735a38`) — `loki.source.kubernetes_events` + `job="k8s-events"` label. RBAC verified live. |
| Grafana auth | OIDC + local login form (break-glass) | ✅ **SSO-only** (`8735a38`) — `disable_login_form: true`; `grafana-admin` secret kept, break-glass documented inline. |
| Object storage (IaC) | `terraform/modules/object-storage/` + `dev/authentik-object-storage/` + `dev/wallabag-s3-backup/` | ❌ **All deleted** (`eb3faf0`). R2 bucket destroyed by user 2026-05-21. **Runtime drift (accepted dev gap):** Authentik manifests still reference R2 → archiving erroring (R-8). |
| Terraform layout | Talos module under `terraform/dev/` | Talos module extracted to `terraform/modules/talos-pve-v3.1.0/` (+ `example/`) to reduce dev/prod duplication (`eb3faf0`). R1/R2 partially addressed — verify cp/worker dup within module. |
| Flux DAG | 15 Kustomizations | **16** — `docs-site` added. |
| CNPG storage | local-path (authentik + freshrss) | Unchanged — still local-path. S-tier not started (the backup capability R-8 defers to). |

---

## Section 2 — Live Cluster Snapshot (2026-05-22, rev `8735a38`)

```
Nodes:      6 Ready — cp-{200,201,202}, node-{203,204,205} — Talos v1.13.0 / k8s v1.35.0 / containerd 2.2.3 / kernel 6.18.24 — 24d
Flux:       16 Kustomizations — cluster-config/controllers/crds/pki/flux-system True@8735a38; rest mid-reconcile dependency-wave (transient, post-push)
HelmReleases: 17/17 Ready (incl. tempo — pending prune once observability reconciles to 8735a38 → will be 16)
Certs:      wildcard-tls Ready (issuer letsencrypt-PRODUCTION) · trust-manager, barman-cloud-{client,server}, op-connect-tls Ready
Workloads:  no pods outside Running/Completed · restart counts all old/low (≤2, 18–24d ago)
PVCs:       authentik (3×5Gi + 3×2Gi-wal local-path) · freshrss (1×2Gi iscsi app + 3×5Gi + 3×2Gi-wal local-path)
            monitoring (alertmgr 5Gi + grafana 5Gi + prom 50Gi + tempo 30Gi[stale], all iscsi)
CNPG:       authentik-dev-cluster 3/3 Ready · ContinuousArchiving=False / LastBackupSucceeded=False (R-8 — expected after R2 decommission)
            freshrss-dev-cluster — local-path, no backup (S-5)
```

Notable:

- **Authentik WAL archiving is erroring every cycle** (R-8) — expected after the R2 decommission; DB itself is Ready. Backup is deferred to the storage sprint; interim fix is removing the dead config.
- **Flux kustomizations were caught mid-wave** — not a fault; re-poll showed the upstream layers already green at `8735a38`.
- **`storage-tempo-0` (30Gi iscsi) is now stale** — Flux will prune the StatefulSet on the next observability reconcile; the PVC must be deleted manually (cascades to the TrueNAS zvol via `RECLAIM_POLICY: Delete`).
- **Every CNPG PVC is still `local-path`** — the S-tier gap, unchanged.
- CCNPs now cover authentik, freshrss, homer, **docs-site** (each default-deny + allow).

---

## Section 3 — Open Items Punch List

Grouped by tier. Each item: **ID · what · status · location · next action.**

### CRITICAL — correctness / data integrity

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| ~~C-2~~ | ~~Wildcard cert on staging~~ | ✅ Done 2026-05-16 | `_lib/networking/gateway/tls.yaml` | — |

(No open CRITICAL items — the Authentik archiving gap is tracked as R-8, an accepted dev gap pending the storage sprint.)

### HIGH — security hardening

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| H-2 | Cilium NetworkPolicies | ✅ Live for all apps (authentik, freshrss, homer, **docs-site**) | `_lib/security/cilium-network-policies/` | **Follow-up:** tighten `world:443` egress to `toFQDNs` once L7 DNS policy is on. |
| H-3 | Falco | ❌ Disabled — **evaluated as the next security tool to add** | `_lib/controllers/kustomization.yaml` (`#  - ./falco`) + `_lib/security/kustomization.yaml` (`#- ./falco-rules`) | Runtime detection is the one missing layer (prevention via Kyverno + Cilium + PSA is solid; Trivy would only add static scanning). ~½ day. Gotchas: (1) the Falco HR uses `crds: CreateReplace` — conflicts with the repo's separate `crds` Flux layer; decide one path. (2) `falco-rules/kustomization.yaml` is an empty stub — needs content or it's a no-op. (3) the `security` ns `namespace.yaml` is commented out of the falco kustomization — confirm the privileged ns label applies. (4) falcoctl egress must be allowed past default-deny. |
| H-4 | ResourceQuotas + LimitRanges | ❌ Not started (grep: **NONE** in `_lib`/`global`) | per-app `base/` | Add `ResourceQuota` + `LimitRange` per app namespace. Seed from `kube dev top pod -n <ns>`. **Authentik server+worker have no resource requests/limits at all** (Kyverno `require-pod-resources` is Audit-only) — start there. Pairs with R-1. |
| H-5 | Trivy operator | ❌ Empty dir | `_lib/security/trivy/` + `_lib/security/kustomization.yaml` (`#- ./trivy`) | Deprioritized below Falco. Populate trivy-operator HR, wire reports → Prometheus/Grafana. |

### MEDIUM — resilience

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| R-1 | PodDisruptionBudgets | ❌ Zero (grep: NONE) | Add `policy/v1 PDB` (`maxUnavailable: 1`) to `_lib/applications/freshrss/base/`. Let CNPG manage its own DB-pod disruption. Homer/docs-site stateless single-replica → skip. |
| R-3 | HPA | ⏸️ Deferred | Stateful single-replica apps; no candidate yet. |
| R-7 | `terminationGracePeriodSeconds` | ⚠️ Not set (grep: NONE) | Set 30–60s on `_lib/applications/freshrss/base/deployment.yaml` so PHP-FPM drains before SIGKILL. |
| R-8 | Authentik CNPG archiving erroring (R2 decommissioned) | 🟡 Accepted dev gap | `ContinuousArchiving=False` since R2 destroyed 2026-05-21. **Interim (cheap):** remove the dead barman-cloud config — `_lib/applications/authentik/overlays/dev/{ob-archiver.enc.yaml,database.yaml}` (barman-cloud plugin) + `_lib/applications/authentik/base/external-secret.yaml` (`authentik-r2-creds`) — to stop `archive_command` errors and unbounded WAL accumulation on the 2Gi WAL PVC. **Real backup** is the S-tier sprint (S-1 → S-2), not this item. Verify: `kube dev -n authentik get cluster -o jsonpath='{.items[0].status.conditions}'`. |

### Performance / capacity (NEW — from perf eval)

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| P-1 | No `metricRelabelings` → apiserver scrape cardinality | ❌ | Add `metricRelabelings` on the apiserver/kubelet ServiceMonitors to drop `apiserver_request_duration_seconds_bucket` / `apiserver_response_sizes_bucket`. Biggest memory lever vs. Prometheus' 2Gi cap. Confirm via Prometheus TSDB head series. |
| P-2 | App resource requests/limits missing | ❌ | Authentik server+worker (and verify others) have no `resources:`; Kyverno enforcement is Audit-only. Set explicit requests/limits. **Overlaps H-4.** |
| P-3 | Kyverno mutation webhook on every pod CREATE | ⚠️ | `add-safe-to-evict` / `disable-service-links` match all Pods (single-replica admission) → admission-path latency. Scope to app namespaces and/or run 2 admission replicas. Drop `pullPolicy: Always` where present. |

### Observability follow-ups

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| ~~O-4~~ | ~~K8s events → Loki~~ | ✅ Done 2026-05-22 (`8735a38`) | `loki.source.kubernetes_events` in `_lib/observability/alloy/configmap.yaml`; RBAC verified. |
| O-5 | Cilium Gateway hardening | ❌ | On exposed HTTPRoutes (grafana, freshrss, authentik, homer, **docs-site**): strip `Server`/`X-Powered-By`, body-size limits, rate limiting via L7 CCNP / CiliumEnvoyConfig. |
| O-6 | Periodic posture scans | ❌ | `popeye` + `kubescape` CronJobs (daily, `Forbid`) → stdout → Loki. |
| ~~O-7~~ | ~~Alertmanager routing~~ | ✅ Done (`67fcd52`) | **Follow-up:** app-specific rules (cert expiry, PVC near-full, **CNPG ContinuousArchiving=False** — would surface R-8-type drift automatically). |
| O-8 | Default-deny CCNP | 🟡 Per-app default-deny landed (incl. docs-site) | No cluster-wide default-deny CCNP — add one for fail-closed on unlabeled namespaces. |
| O-9 | App-level dashboards/alerts | ❌ | FreshRSS, Authentik — flip Authentik chart `serviceMonitor.enabled: true`. |

### Homer / docs-site follow-ups

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| HM-1 | Homer read-only root FS | ⚠️ `readOnlyRootFilesystem: false` | `_lib/applications/homer/base/deployment.yaml` | Enumerate writable paths (theme seed into `/www/assets`), mount as `emptyDir`, flip to RO. |
| HM-2 | Homer service-tile content | ❓ Verify | `_lib/applications/homer/base/configmap.yaml` | Confirm tiles list live hosts incl. **docs-site** (`dev.int.docs`). |
| DS-1 | docs-site living-scaffold pages are manual | ⚠️ | `_docs/status.md`, `_docs/roadmap.md` | `status.md` (service status) is hand-maintained; `roadmap.md` pulls from the newest review — refresh both when apps land. |

### Storage migration (S-tier — from `storage-strategy-decision.md`)

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| S-1 | Snapshot infrastructure | ❌ Absent | `global/crds/`, `_lib/storage/freenas-csi/` | Add `external-snapshotter` CRDs + snapshot-controller, enable democratic-csi snapshotter sidecar, create `VolumeSnapshotClass`. Verify a manual snapshot. **Blocks S-2.** |
| S-2 | CNPG → single-instance static iSCSI zvol | ❌ Not started | `_lib/applications/{authentik,freshrss}/overlays/dev/` | Pre-create zvols + static `Retain` PVs; CNPG `instances: 1`; static `pvcTemplate.volumeName`. Verify operator `0.27.0` honors `volumeName` on a throwaway cluster first. |
| S-3 | Retire R2/S3 from CNPG path | 🟡 IaC removed (`eb3faf0`); runtime still references it (R-8) | authentik overlay | Removing the dead barman-cloud manifests is tracked as R-8 (interim); the snapshot-based replacement is S-2. |
| S-4 | iscsi StorageClass reclaim default | ⚠️ `Delete` | `_clusters/dev/config/cluster-configs.yaml` (`RECLAIM_POLICY`) | Flip to `Retain` so accidental dynamic iscsi volumes survive PVC deletion. (Note: `Delete` is what lets the stale Tempo PVC cleanup cascade to the zvol — intended here, risk elsewhere.) |
| S-5 | freshrss CNPG has no backup | ⚠️ Gap | `_lib/applications/freshrss/overlays/dev/database.yaml` | Resolved by S-2 VolumeSnapshot ScheduledBackup. |

### Hygiene / cleanup

| Item | Location | Action |
| ---- | -------- | ------ |
| Stale Tempo PVC | `monitoring/storage-tempo-0` (30Gi iscsi) | After observability reconciles to `8735a38` and prunes the STS: `kube dev -n monitoring delete pvc storage-tempo-0` (cascades to TrueNAS zvol). |
| CryptPad TrueNAS zvol | `dev-cryptpad-data-pvc` | ❓ Confirm destroyed (last CryptPad cleanup step). |
| Placeholder cluster | `_clusters/production/` | Leave until prod promotion. |

### Terraform / IaC

| ID | Item | Status | Note |
| -- | ---- | ------ | ---- |
| TF-CoreDNS | Apply CoreDNS split-horizon inlineManifest | ⚠️ Committed (`8b3af1f`), apply unverified | `terraform/dev/.../talos.tf`. Live runs the manual edit; a rebuild without applying reverts the DNS fix. `/terraform-plan` → `/terraform-apply`. |
| ~~TF-wallabag~~ | ~~Destroy dead wallabag S3 stack~~ | ✅ Done — IaC removed (`eb3faf0`); S3 bucket + IAM destroyed (confirmed 2026-05-22) | — |
| R1 | Collapse `pve.tf` cp/worker duplication | 🟡 Partially | Talos module extracted to `terraform/modules/talos-pve-v3.1.0/` (`eb3faf0`) — reduces dev/prod dup. Verify cp/worker duplication *within* `pve.tf` is also collapsed. |
| R2 | Extract shared Talos machine config | 🟡 Partially | Same module extraction. Verify worker still lacks CP-only PSA exemptions (drift risk). |
| R5 | Worker memory typo `8092` | ⚠️ | `terraform/dev/variables.tf` + `terraform.tfvars` — tidy next tfvars edit. |

### Manual / non-GitOps

| Item | Status | Note |
| ---- | ------ | ---- |
| Beelink S13 BIOS power-loss = "Power On" | ❓ Unverified | Pairs with Proxmox HA for power-blip self-recovery. |
| system-upgrade-controller for Talos | ⏸️ Hack-only | `_hack/scripts/upgrade.sh` exists; not deployed via Flux. |
| SSO public exposure (Phase 4) | ⏸️ Not started | Cloudflare Tunnel + forward-auth outposts; Cloudflare WAF terraform not built. |

---

## Section 4 — Thoth (unified knowledge app) & future apps — Status

**Thoth** — descoped (user, 2026-05-22): **no plans for a full-fledged app**; focus is useful utilities/scripts and iterating on existing infra. ADR-0005 (`_docs/decisions/`) should be updated from Draft to reflect this (no MinIO/Meilisearch/NATS/Ollama/Istio build commitment). The "DR for MinIO-backed notes" question is moot.

**docs-site** — ✅ **Live** (new since baseline). Internal `dev.int.docs.home-0ps.com`. Polish tracked as DS-1 (manual living-scaffold pages).

**GPU sharing** — pre-decision doc (`_docs/decisions/0004…`), recommends single-node VFIO passthrough on HP Slim S01.

---

## Section 5 — Suggested Next Sprint

In order, cut at natural stopping points:

1. **H-4 + R-1 + R-7 (freshrss)** — ResourceQuota/LimitRange + PDB + terminationGracePeriod, one namespace, one PR.
2. **H-3 — enable Falco** (the evaluated next security tool); resolve the CRD-ownership decision first.
3. **P-1 — apiserver `metricRelabelings`** — cheap memory win vs. Prometheus' 2Gi cap.
4. **Hygiene:** R-8 (strip dead Authentik R2 barman-cloud config — stops archiving errors); delete stale Tempo PVC; verify TF-wallabag cloud resources destroyed; ADR-0005 Thoth descope.
5. **Storage S-tier — its own sprint** (S-1 snapshot infra → S-2 authentik+freshrss → S-4 reclaim) — establishes the real backup capability that R-8 defers to.
6. **O-5/O-6** gateway hardening + posture scans; **O-9** app dashboards; terraform R1/R2/R5 verification.

---

## Section 6 — Files Referenced

| File | Why it matters |
| ---- | -------------- |
| `_lib/applications/authentik/overlays/dev/{ob-archiver.enc.yaml,database.yaml}` | R-8 — barman-cloud archiving still targets destroyed R2 bucket |
| `_lib/applications/authentik/base/external-secret.yaml` | R-8 — `authentik-r2-creds` ExternalSecret to remove |
| `_lib/applications/docs-site/` | New live app (base + overlay) |
| `_lib/observability/kustomization.yaml` | Tempo removed; alloy + scrape-configs remain |
| `_lib/observability/alloy/configmap.yaml` | O-4 k8s events → Loki (done) |
| `_lib/observability/kube-prometheus-stack/helmrelease.yaml` | Grafana SSO-only + Tempo datasource removed |
| `_lib/security/{controllers,security}/kustomization.yaml` | Falco still commented (H-3) |
| `_lib/security/cilium-network-policies/` | CCNPs for authentik/freshrss/homer/docs-site |
| `_clusters/dev/cluster.yaml` | 16-Kustomization DAG; `docs-site` added |
| `_clusters/dev/config/cluster-configs.yaml` | `RECLAIM_POLICY: Delete` (S-4); DOCS_VERSION |
| `terraform/modules/talos-pve-v3.1.0/` | Extracted Talos module (R1/R2 partial) |
| `terraform/dev/` (object-storage dirs removed) | object-storage + authentik-object-storage + wallabag-s3-backup deleted (`eb3faf0`) |
| `_docs/storage-strategy-decision.md` | S-tier — establishes the backup capability R-8 defers to |
| `_docs/reviews/home-0ps-review-2026-05-20.md` | Prior review — superseded by this one |
