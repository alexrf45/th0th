# home-0ps.com Review — 2026-06-08

> Generated: 2026-06-08 (`/lab-review`). Supersedes `home-0ps-review-2026-05-29.md`.
> Scope: **Repo state only — the `memphis` dev cluster is fully spun down.** The live
> survey is N/A: `163b8e3 "Uninstall Flux"` removed the Flux bootstrap manifests and the
> `memphis-kubeconfig` 1Password item no longer exists (destroyed with the cluster). All
> live-runtime findings from the baseline are **paused → re-verify on redeploy**, not resolved.
> Trigger: **Return-from-hiatus / teardown + Proxmox-foundation rebuild.** Post-baseline work is
> docs polish + `Uninstall Flux` (committed) and a net-new **`terraform/proxmox-base/`** root
> (admin user + RBAC + automation token + SDN Simple zone) plus a Talos-module bridge param —
> all **uncommitted** in the working tree.

---

## Executive Summary

The lab moved from a live, healthy 6-node `memphis` cluster (baseline 2026-05-29) to a
**deliberate full spin-down**, and the focus shifted to **rebuilding the Proxmox foundation**
before re-deploying Talos.

Committed since the baseline review (`b5e71cb..HEAD`, all dated 2026-05-29, mostly README/docs):
- **Public bootstrap-guide site** (`2e74246` #52 + `54f7290`) — MkDocs Material (gruvbox) + D2
  diagrams + docs restructure into how-to (`a228578`, `41244e1`, `9a01031`).
- **`163b8e3 Uninstall Flux`** — deleted `_clusters/dev/flux-system/{gotk-components,gotk-sync,
  kustomization}.yaml` (6469 lines). The cluster's GitOps tree (`_lib/`, `cluster.yaml`'s 16-layer
  DAG) is **preserved** for re-bootstrap; only the bootstrap entrypoint was removed.

Uncommitted working tree — **the active workstream**:
- **`terraform/proxmox-base/` (NEW)** — persistent TF root, own S3 state, mirrors
  `terraform/cloudflare-tunnel/`. Provisions `admin@pve` (PVEAdmin), `terraform@pve` + custom role
  + `proxmox_user_token` (→ 1Password), and a **SDN Simple zone** `talos` → vnet `vtalos` → subnet
  `10.30.0.0/24` (SNAT) → applier. `terraform validate` passes. **Not yet applied.**
- **Talos module** `var.pve.bridge` param (default `vmbr0`) so a future single-host VNet move is one variable.
- **`cluster-configs.yaml`** — TrueNAS dataset reorg: `DATASET_PARENT` `home-share/iscsi/k8s/dev/volumes`
  → `home-share/k8s/dev`, snapshots path likewise (matches the manual TrueNAS PVE-plugin + iSCSI rework).
- `_hack/portainer/loki` tailscale image `v1.78` → `v1.98.4`; `best-practices.md` bpg-deprecation note.

**Recommended next sprint:** **apply `terraform/proxmox-base/`** (admin user + RBAC + SDN), **then
resolve PB-4** (Simple zone can't host the HA cluster — pick VXLAN/EVPN or endpoint redesign) **before
re-bootstrapping `memphis`**. Commit the uncommitted foundation work first.

---

## Section 1 — What Changed Since 2026-05-29

| Area | 2026-05-29 state | 2026-06-08 state |
| ---- | ---------------- | ---------------- |
| **Cluster lifecycle** | Live: 6 nodes Ready, 17 Kustomizations/HRs Ready | 🗑️ **Spun down.** `Uninstall Flux` (`163b8e3`) removed `flux-system/`; `memphis-kubeconfig` 1P item gone. `cluster.yaml` DAG + `_lib/` retained. |
| **Proxmox base (NEW)** | — (all access as root@pam, no RBAC, no SDN) | 🟡 **Authored, not applied.** `terraform/proxmox-base/`: admin user, automation user/role/token, SDN Simple zone. `validate` green. PB-1..PB-6. |
| **Proxmox SDN (NEW)** | None | 🟡 Simple zone `talos`/`vtalos`/`10.30.0.0/24` SNAT coded. **Constraint:** no cross-node L2 → can't host HA cluster as-is (PB-4). |
| **TrueNAS storage** | `home-share/iscsi/k8s/dev/volumes` datasets | 🟡 Reorg to `home-share/k8s/dev` (cluster-configs.yaml, **uncommitted**) — pairs with manual PVE TrueNAS-plugin + iSCSI setup. CFG-1. |
| **Talos module** | bridge hardcoded `vmbr0` | ✅ `var.pve.bridge` (default `vmbr0`); no behavior change. PB-6. |
| **Public docs site** | (in-cluster MkDocs retired 2026-05-26) | ✅ NEW external bootstrap-guide: MkDocs Material gruvbox + D2, CF Pages (`#52`). |
| **Off-cluster Loki host** | tailscale `v1.78` | 🟡 `v1.98.4` (uncommitted hygiene). |
| **All live observability/security items** | Verified live (O-*, H-*, Hyg-2, etc.) | ⏸️ **Paused** — unverifiable while cluster down; repo config unchanged, carries forward. |
| **Dev tip** | `b5e71cb` (review at `a6458fc`) | `163b8e3` (+22 commits, 21 docs/README + 1 teardown) + uncommitted working tree |

---

## Section 2 — Live Cluster Snapshot

**N/A — cluster spun down.** `kube dev …` fails at kubeconfig fetch: the `memphis-kubeconfig`
1Password Secure Note (exported by the now-destroyed Terraform run) is gone. No nodes, no Flux, no
workloads to survey. The next snapshot will be regenerated post-redeploy.

Repo-state facts confirmed in lieu of a live survey:
- `_clusters/dev/cluster.yaml` — 16 Kustomization layers intact (DAG ready for re-bootstrap).
- `_clusters/dev/flux-system/` — **removed** (only `config/` + `cluster.yaml` remain under `_clusters/dev/`).
- `terraform/proxmox-base/` — 7 files, `terraform validate` passes (benign bpg `acl` deprecation warning only).
- Working tree dirty: `terraform/proxmox-base/` (untracked) + 5 modified files (see Section 1); **0 of it committed.**

---

## Section 3 — Open Items Punch List

Grouped by tier. Each item: **ID · what · status · location · next action.**
**Note:** the cluster is down — every live-runtime item below is ⏸️ *paused, re-verify on redeploy*;
the repo config behind it is unchanged from baseline (0 commits touched `_lib/`).

### CRITICAL — gating the rebuild

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| **CLUSTER-0** | **Re-deploy `memphis`** (Talos + Flux bootstrap) | ❌ **Open — the macro-task** | `terraform/dev/`, `_clusters/dev/cluster.yaml` | After PB-1..PB-4: re-add `flux-system/` bootstrap (or `flux bootstrap` via TF), `terraform apply` dev with `bootstrap_cluster = true`. Verify 6 nodes Ready + Kustomizations reconcile. |
| **PB-4** | **SDN Simple zone can't host the HA cluster** (no cross-node L2 → breaks Talos VIP + Cilium L2 LB) | ❌ **Open — decision needed before VNet migration** | `terraform/proxmox-base/sdn.tf` | Decide: **VXLAN/EVPN zone** (stretched L2) vs **control-plane-endpoint redesign** (drop L2 VIP). Write an ADR in `_docs/decisions/`. Simple zone is fine for single-host validation only. |

### Proxmox foundation (PB-tier — NEW workstream)

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| **PB-1** | Admin user + RBAC + automation token | 🟡 Coded, not applied | `terraform/proxmox-base/{users.tf,providers.tf}` | Phase-1 `apply` (root@pam) → creates `admin@pve` (PVEAdmin), `terraform@pve` + role + token→1P. Verify in Datacenter → Permissions. |
| **PB-2** | SDN Simple zone + vnet + subnet + applier | 🟡 Coded, not applied | `terraform/proxmox-base/sdn.tf` | `apply`; confirm Datacenter → SDN shows `talos`/`vtalos`/`10.30.0.0/24` **applied** (not pending). Smoke-test a throwaway VM on bridge `vtalos` (SNAT egress). |
| **PB-3** | Provider auth cutover → token (Phase 2) | ❌ Open (after PB-1) | `terraform/proxmox-base/providers.tf` + `terraform/dev/providers.tf` | Set `TF_VAR_pve_api_token` from the 1P `proxmox-terraform-token` item, re-plan both roots (no diff). Dev `providers.tf` still uses root@pam — wire the same conditional. |
| **PB-5** | Manual prereqs: 1P admin item + tfvars + backend, SOPS-encrypt | ❌ Open (user) | `terraform/proxmox-base/{terraform.tfvars,remote.tfbackend}` | Pre-create 1P `proxmox-admin` (password field); fill tfvars (endpoint `192.168.20.6`, hosts `pve01..pve06`); `key=state/proxmox-base/v1.tfstate`; **SOPS-encrypt before commit**. |
| **PB-6** | Talos module bridge param | ✅ Done (coded) | `terraform/modules/talos-pve-v3.1.0/{pve.tf,variables.tf}` | `var.pve.bridge` default `vmbr0`. Future VNet move = set `bridge="vtalos"` + new subnet/IPs. |
| **PB-7** | Commit the uncommitted foundation work | ❌ Open | working tree | `terraform/proxmox-base/`, module bridge, cluster-configs reorg, loki bump, best-practices note all uncommitted — branch + commit (SSH-signed by user). |

### Config / storage

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| **CFG-1** | TrueNAS dataset path reorg | 🟡 Uncommitted | `_clusters/dev/config/cluster-configs.yaml` | `DATASET_PARENT`→`home-share/k8s/dev`. Confirm the live TrueNAS dataset layout matches before redeploy (democratic-csi will create under it). Commit with PB-7. |

### HIGH — security hardening (⏸️ paused, repo config carried forward)

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| H-2 | Cilium NetworkPolicies — `world:443` egress tightening | ⚠️ Open | `_lib/security/cilium-network-policies/` | Tighten to `toFQDNs` once L7 DNS policy on. Consult [[cilium-gateway-egress-l7-filter]]. |
| H-5 | Trivy operator | ❌ Empty dir | `_lib/security/trivy/`, `_lib/security/kustomization.yaml` | Populate HR, wire reports → Prometheus/Grafana. |
| O-5 / G2-2 | Gateway + public-surface hardening | 🟡 Rate-limit done; headers/WAF open | exposed HTTPRoutes + public hostnames | Strip `Server`/`X-Powered-By`, body-size limits; Cloudflare managed WAF. |

### MEDIUM — resilience

| ID | Item | Status | Next action |
| -- | ---- | ------ | ----------- |
| R-3 | HPA | ⏸️ Deferred | Stateful single-replica apps; no candidate. |

### Observability follow-ups (⏸️ all paused — cluster down)

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| O-6 | Periodic posture scans | ❌ | — | `popeye` + `kubescape` CronJobs → Loki. |
| O-8 | Cluster-wide default-deny CCNP | 🟡 Per-app done | — | Add cluster-wide default-deny for unlabeled namespaces. |
| O-10 | App-data dashboards (postgres-exporter) | ❌ Open | `_lib/observability/` | Shared exporter for the 3 CNPG clusters; mind [[cilium-gateway-egress-l7-filter]] (CCNP egress :5432). |
| O-14 | Codify "audit community configs" rule | ❌ Open | `.claude/rules/` (proposed) | Spot-check label vocabularies vs this cluster's series before merging community PromQL/dashboards. |
| O-15 | kromgo `flux_version` badge "No Data" — KSM label allowlist | ⏸️ Paused (kromgo down) | kps HR + kromgo `config.yaml` | KSM `metricLabelsAllowlist` + query rewrite (full recipe in 2026-05-29 review). Re-verify on redeploy. |
| O-17 | authentik metrics TargetDown × 2 | ⏸️ Paused | `_lib/observability/kube-prometheus-stack/servicemonitor-authentik.yaml` + `_lib/applications/authentik/overlays/dev/` | Was firing pre-teardown. On redeploy: `kube dev -n authentik get svc \| grep metrics` + describe endpoints. |
| O-18 | tailscale-operator PodMonitor 0 targets | ⏸️ Paused ❓ | `tailscale` ns, ts-operator chart | On redeploy: check podmonitor selector vs pod labels. |

### Homer

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| HM-1 | Homer read-only root FS | ⚠️ `readOnlyRootFilesystem: false` | `_lib/applications/homer/base/deployment.yaml` | Enumerate writable paths, mount `emptyDir`, flip to RO. |

### Storage migration (S-tier — COMPLETE)

| ID | Item | Status | Notes |
| -- | ---- | ------ | ----- |
| ~~S-1..S-6~~ | (all closed) | ✅ | ADR-0003. Note CFG-1 dataset reorg + redeploy will re-create CNPG clusters from static PVs. |

### Sprint orchestrator

| ID | Item | Status | Location | Next action |
| -- | ---- | ------ | -------- | ----------- |
| SO-2 | First-run polish | 🟡 Open | `.claude/commands/sprint-orchestrate.md` | Document session-limit recovery + cherry-pick path. |
| SO-3 | Sprint-state.json schema versioning | 🟡 Open | `.claude/sprint-state.json` | Add `"schema_version"`. |

### Hygiene / cleanup

| ID | Item | Location | Action |
| -- | ---- | -------- | ------ |
| Hyg-1 | Placeholder cluster | `_clusters/production/` | Leave until prod promotion. |
| Hyg-2 | Orphan Falco Redis PVC | (was) `security` ns | ⏸️ Likely moot post-teardown — verify the TrueNAS zvol/PV was cleaned; StatefulSet stays off. |
| Hyg-3 | yamllint comment warnings | `_clusters/dev/config/cluster-configs.yaml` + prod | Add space after `#`. Non-blocking. |
| Hyg-4 | Loki tailscale bump uncommitted | `_hack/portainer/loki/docker-compose.yaml` | `v1.78`→`v1.98.4`; commit with PB-7. |

### Terraform / IaC

| ID | Item | Status | Note |
| -- | ---- | ------ | ---- |
| I-1 | Talos `kubernetes_version` pinned v1.12.8 | ⚠️ Open | `terraform/dev/`. Revisit at 1.36.0. |
| R5 | Worker memory typo `8092` | ⚠️ Open | `terraform/dev/variables.tf` + tfvars — tidy on next tfvars edit (redeploy touches this). |
| R1/R2 | pve.tf dedup + shared machine config | 🟡 Verify post-refactor | — |
| Sprint 6 | Node-label apply-ordering | ⏸️ Deferred (ADR-0006 #15) | Retry-on-apply workaround stands; will hit on redeploy. |

### Manual / non-GitOps

| Item | Status | Note |
| ---- | ------ | ---- |
| TrueNAS PVE plugin + shared iSCSI | ✅ Done (manual, this session) | Pairs with CFG-1 dataset reorg. |
| Proxmox admin user + SDN | 🟡 In progress | See PB-tier. |
| Beelink S13 BIOS power-loss = "Power On" | ❓ Unverified | Re-confirm on each node during rebuild. |
| system-upgrade-controller for Talos | ⏸️ Hack-only | `_hack/scripts/upgrade.sh`. |
| SSO public exposure (Phase 4) | ⏸️ Blocked on redeploy | Cloudflare Tunnel infra persists (own state). |

---

## Section 4 — Thoth & future apps — Status

- **Thoth** — ✅ Descoped (ADR-0005). No change.
- **Cloudflare Tunnel** — ✅ Persists (own TF state, survives teardown). Will front services again post-redeploy.
- **Proxmox base / SDN** — 🟡 NEW workstream (PB-tier). See [[project_proxmox_base_tf_root]].
- **GPU sharing** — pre-decision (ADR-0004) unchanged.
- **All in-cluster apps** (Authentik, FreshRSS, Homer, Gatus, kromgo, Falco) — ⏸️ offline (cluster down); manifests intact, return on CLUSTER-0.

---

## Section 5 — Suggested Next Sprint

In order, cut at natural stopping points:

1. **PB-5 prereqs + PB-1/PB-2 apply** — create 1P admin item, fill+SOPS tfvars/backend, `terraform apply terraform/proxmox-base` (Phase 1). Verify users + SDN applied. Natural cut.
2. **PB-7 commit** — branch + SSH-signed commit of the foundation work (proxmox-base, bridge param, CFG-1, loki bump, best-practices note).
3. **PB-4 decision (ADR)** — VXLAN/EVPN vs endpoint redesign for hosting the HA cluster on a VNet. Gates any real Talos-on-VNet move.
4. **PB-3 token cutover** — flip both provider blocks to the automation token.
5. **CLUSTER-0 redeploy** — re-bootstrap `memphis` (Talos + Flux). Confirm CFG-1 dataset paths against live TrueNAS first. On the way back up, R5/Sprint-6/I-1 Terraform housekeeping naturally fall in.
6. **Post-redeploy** — re-verify the paused observability/security punch list (O-15/O-17/O-18, Hyg-2) against the live cluster; regenerate the live snapshot.

---

## Section 6 — Files Referenced

| File | Why it matters |
| ---- | -------------- |
| `terraform/proxmox-base/users.tf` | NEW — admin@pve (PVEAdmin) + terraform@pve role/ACL/token; token → 1P. Manage perms via `proxmox_acl`, never inline `acl{}` (benign bpg deprecation warning). |
| `terraform/proxmox-base/sdn.tf` | NEW — Simple zone/vnet/subnet/applier. **Constraint:** no cross-node L2 (PB-4). |
| `terraform/proxmox-base/providers.tf` | NEW — two-phase auth (root@pam → token via `pve_api_token`). |
| `terraform/proxmox-base/terraform.tfvars.example` | NEW — fill template; real values endpoint `192.168.20.6`, hosts `pve01..pve06`. |
| `terraform/modules/talos-pve-v3.1.0/{pve.tf,variables.tf}` | `var.pve.bridge` param (PB-6) — one-variable VNet move later. |
| `_clusters/dev/config/cluster-configs.yaml` | TrueNAS dataset reorg (CFG-1, uncommitted). |
| `_clusters/dev/cluster.yaml` | 16-layer DAG intact; the re-bootstrap spine (CLUSTER-0). |
| `_clusters/dev/flux-system/` | **Removed** by `163b8e3`; must be re-created for redeploy. |
| `_docs/guides/best-practices.md` | §1 — bpg `acl` deprecation note added this session. |
| `_docs/reviews/home-0ps-review-2026-05-29.md` | Prior baseline (live-cluster state); all live findings carry forward as ⏸️ paused. |
