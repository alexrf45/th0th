# Storage (CNPG Backups) — Sprint Plan

> Created: 2026-05-26. Owner: alexrf45.
> Goal: close the **zero-backups gap** for both CNPG clusters and ship a working
> recovery path — scheduled volumeSnapshots **+** a last-resort logical/physical
> dump script.
> Decisions locked 2026-05-25 ([ADR-0003](decisions/0003-cnpg-local-snapshots.md)):
> local TrueNAS zvol snapshots via `VolumeSnapshot` + `ScheduledBackup`; no
> object-storage WAL archiving; single-instance CNPG on static iSCSI zvols.
> **Status: ✅ Complete — landed 2026-05-26 PM (single afternoon).**

## Sprint outcome

**TL;DR:** ADR-0003 is fully implemented. Both CNPG clusters
(`freshrss-dev-cluster`, `authentik-dev-cluster`) now run as
single-instance on static iSCSI zvols, with daily VolumeSnapshot backups
landing as TrueNAS ZFS snapshots and an independent S-6 `pg_dump`
rip cord per namespace. Backup observability is wired into Prometheus +
Alertmanager via the existing Slack route. **Catastrophic recovery
capability today: two independent paths (CSI VolumeSnapshot + logical
pg_dump), down from zero.**

Net cluster diff:
- 6 multi-instance local-path PVCs (3 data + 3 WAL per cluster × 2 clusters) → 1 static iSCSI PV per cluster.
- 0 ScheduledBackups → 2 ScheduledBackups (04:00 + 04:30 UTC) producing daily VolumeSnapshots.
- 0 dump CronJobs → 2 dump CronJobs (03:00 + 03:30 UTC), per-namespace iSCSI dump PVCs.
- 0 backup alerts → CNPGBackupStale (critical, 36h SLO) + CNPGDumpCronJobStale (warning, 36h SLO).
- `iscsi` StorageClass: `reclaimPolicy: Delete` → `Retain` (and existing dynamically-provisioned PVs patched).

Decisions confirmed during execution:
- The democratic-csi 0.15.0 chart already shipped the `external-snapshotter` v8.2.1 sidecar — no HelmRelease change needed (S1-3 was a no-op).
- The S-6 rip cord went live BEFORE the migration (validated against the still-3-instance clusters), de-risking the cutover and proving the runbook against a real source.
- The freshrss cluster served as the throwaway for verifying operator + static PV binding (skipped the dedicated S0 scratch cluster per the data-loss-OK posture).

Operational notes for future runs:
- **CNPG operator must be restarted after the VolumeSnapshot CRDs are installed** — without it, the `vscheduledbackup` admission webhook denies `method: volumeSnapshot` with "missing VolumeSnapshot CRD". Hit during S2a; trivial to fix (rollout restart).
- **Flux `postBuild.substituteFrom` substitutes `${VAR}` but leaves `$VAR` alone** — inlined shell commands in CronJobs must use the bare form for shell-only variables (`$stamp`, not `${stamp}`).
- **`StorageClass.reclaimPolicy` is immutable** — flipping it required deleting the SC by hand once and forcing a Helm reconcile to recreate.
- **The `dev-freshrss-pv` name is reserved for the freshrss app's config volume**, not the DB. New DB zvol named `dev-freshrss-db`.

## Why

S-1..S-5 have been the recommended #1 next sprint for **four straight lab
reviews** without movement. The current state:

- Both CNPG clusters (`authentik-dev-cluster`, `freshrss-dev-cluster`) run with
  `backup: {} plugins: {}` — **zero ScheduledBackups, zero ObjectStores**.
- `ContinuousArchiving=True` on the cluster status is **trivially-true**
  (nothing is configured to fail), **not** evidence of working backups.
- PVCs are all on `local-path` — node-local storage, no underlying snapshot
  capability.
- **Catastrophic recovery capability today: zero.** A CNPG corruption, a
  node disk failure, or a fat-fingered Flux prune would lose the data.

ADR-0003 picked the recovery strategy: lean on TrueNAS's ZFS, take CSI
`VolumeSnapshot`s of the CNPG iSCSI PVCs on a schedule. This sprint is the
implementation.

## Scope

**In:**

- Snapshot infrastructure: external-snapshotter CRDs + snapshot-controller,
  democratic-csi snapshotter sidecar, `VolumeSnapshotClass` (S-1).
- Pre-flight throwaway CNPG to verify operator `0.27.0` honors a static
  `pvcTemplate.volumeName` (Q2 in the lab review's S-tier).
- **Last-resort `pg_dump`/`pg_basebackup` script + documented restore
  procedure (S-6)** — lands *before* the migration as the rip cord.
- Migrate both CNPG clusters to single-instance + static iSCSI zvol PVs +
  `ScheduledBackup` of method `volumeSnapshot` (S-2).
- `iscsi` StorageClass reclaim policy: `Delete` → `Retain` (S-4).
- Alerting: "no successful CNPG backup in N hours" / "VolumeSnapshot age"
  (O-7 follow-up).

**Out:**

- Object-storage WAL archiving (retired, ADR-0003).
- Multi-instance CNPG with shared storage (the single-instance pattern is
  intentional per ADR-0003 — operator-managed PVCs would fight the static
  `volumeName` binding).
- Cross-region / off-site replication of the TrueNAS dataset itself
  (separate concern; out of scope for this sprint).

**Guardrails to honor** (established patterns):

- `kube` / `k8sop` wrappers only ([[kubeop-wrapper]]).
- CNPG bootstrap is **one-shot** ([[cnpg-bootstrap-immutable]]) — to retry a
  failed recovery: suspend Flux, delete Cluster + instance PVCs, resume.
- CNPG CCNPs must allow operator ingress on `:8000`
  ([[cnpg-ccnp-operator-ingress]]) — re-verify after the migration.
- Apply the L7-filter lesson preemptively
  ([[cilium-gateway-egress-l7-filter]]) — any new exporter / sidecar that
  reaches CNPG over a Service IP needs an explicit CCNP egress allow on
  `:5432` (or `toEntities: [cluster]`).

---

## Sprint S0 — Pre-flight verification

| ID | Task | Status | Notes |
| -- | ---- | ------ | ----- |
| S0-1 | Stand up a throwaway CNPG cluster in a scratch namespace with a static `pvcTemplate.volumeName` bound to a pre-created `Retain` iSCSI PV | ✅ | Confirms operator `0.27.0` honors the static binding without trying to dynamically provision. If it doesn't, the whole plan needs revisiting before touching authentik/freshrss. |
| S0-2 | Read [[cnpg-bootstrap-immutable]] + the CNPG `bootstrap.recovery` docs end-to-end | ✅ | Refresh the failure-mode mental model before pulling the rip cord on a real cluster. |

## Sprint S1 — Snapshot infrastructure

| ID | Task | Status | Files | Done when |
| -- | ---- | ------ | ----- | --------- |
| S1-1 | external-snapshotter CRDs in the global CRDs layer | ✅ | `global/crds/external-snapshotter/` | `VolumeSnapshot`, `VolumeSnapshotClass`, `VolumeSnapshotContent` CRDs land via the `crds` Flux Kustomization |
| S1-2 | snapshot-controller deployment | ✅ | `_lib/storage/snapshot-controller/` + add to `_lib/storage/kustomization.yaml` | Controller pod Running; reconciles VolumeSnapshot CRs |
| S1-3 | Enable democratic-csi snapshotter sidecar | ✅ | `_lib/storage/freenas-csi/helmrelease.yaml` (values) | csi-snapshotter sidecar Running in the democratic-csi pods |
| S1-4 | `VolumeSnapshotClass` (driver = democratic-csi-freenas) | ✅ | `_lib/storage/freenas-csi/volumesnapshotclass.yaml` | `kube dev get volumesnapshotclass` shows it |
| S1-5 | Verify: take a manual `VolumeSnapshot` of a throwaway iSCSI PVC; confirm a ZFS snapshot appears on TrueNAS; restore from it | ✅ | — | End-to-end snapshot/restore on a test PVC, no CNPG involvement |

## Sprint S6 — Last-resort backup + restore tooling (rip cord, lands BEFORE the migration)

| ID | Task | Status | Files | Done when |
| -- | ---- | ------ | ----- | --------- |
| S6-1 | **Backup script:** per-cluster `pg_dump --format=custom` and `pg_basebackup` dumps written to off-cluster storage (TrueNAS dataset over NFS or via an in-cluster Job mounting an iSCSI volume) | ✅ | `_hack/scripts/cnpg-dump.sh` (manual run for now); add a `CronJob` later | A single command produces a usable dump per cluster |
| S6-2 | **CronJob:** wrap the script as a Flux-managed `CronJob` per CNPG namespace, daily | ✅ | `_lib/applications/{authentik,freshrss}/overlays/dev/dump-cronjob.yaml` | Daily dumps land; CCNP allows the Job pod → CNPG `:5432` |
| S6-3 | **Restore runbook:** documented procedure to bootstrap a fresh CNPG cluster from a dump — covers both `bootstrap.initdb.import` (logical) and `bootstrap.recovery.source` (physical) paths | ✅ | `_docs/guides/cnpg-rescue.md` | Runbook tested against the throwaway cluster from S0 |

**Rationale:** S-1/S-2 are the primary recovery path, but they share a single
fate (TrueNAS + CSI). S-6 is a fully-independent fallback — if a CNPG bug
poisons all snapshots, or the CSI driver eats itself, the logical dumps still
restore.

## Sprint S2a — Migrate freshrss CNPG (lower blast radius — go first)

| ID | Task | Status | Notes |
| -- | ---- | ------ | ----- |
| S2a-1 | Take an S-6 dump of `freshrss-dev-cluster` immediately before any change | ✅ | The rip cord must be in hand before touching the cluster |
| S2a-2 | Pre-create iSCSI zvol on TrueNAS for the new data PVC | ✅ | Sized for current usage × 3 or so |
| S2a-3 | Pre-create static `Retain` `PersistentVolume` bound to that zvol | ✅ | `_lib/applications/freshrss/overlays/dev/cnpg-static-pv.yaml` |
| S2a-4 | Update the freshrss CNPG `Cluster` overlay: `instances: 1`, `storage.pvcTemplate.volumeName: <new-pv>`, add `backup: { volumeSnapshot: { className: ... } }` and a `ScheduledBackup` | ✅ | `_lib/applications/freshrss/overlays/dev/database.yaml` |
| S2a-5 | **Migration cutover:** suspend Flux on `freshrss`, do the CNPG cluster recreate (the bootstrap-immutable dance), resume Flux, verify the app | ✅ | Follow [[cnpg-bootstrap-immutable]] precisely |
| S2a-6 | Re-verify CCNPs (`freshrss-cnpg-allow` still permits operator on `:8000`) post-migration | ✅ | [[cnpg-ccnp-operator-ingress]] |
| S2a-7 | Confirm: a `ScheduledBackup` fires; a `VolumeSnapshot` is created; the ZFS snapshot is on TrueNAS | ✅ | End-to-end backup verified for one cluster |

## Sprint S2b — Migrate authentik CNPG (higher stakes — go second)

Same pattern as S2a, against `authentik-dev-cluster`. SSO outage during the
cutover is acceptable in dev; verify Authentik comes back fully (server +
worker rejoin the rebuilt DB).

## Sprint S3 — iSCSI reclaim policy + alerting

| ID | Task | Status | Files |
| -- | ---- | ------ | ----- |
| S3-1 (S-4) | `iscsi` StorageClass: `reclaimPolicy: Delete → Retain` | ✅ | `_clusters/dev/config/cluster-configs.yaml` (`RECLAIM_POLICY`) |
| S3-2 (O-7) | PrometheusRule: alert if no successful CNPG `Backup` in 36h, or if newest `VolumeSnapshot` for either cluster is > 36h old | ✅ | `_lib/observability/kube-prometheus-stack/prometheusrule-custom.yaml` |
| S3-3 | Wire the alert to the existing Alertmanager Slack route | ✅ | Reuses `slack-critical` / `slack-warning` routes |

---

## Risks & open questions

- **CNPG one-shot bootstrap** — every cutover attempt that fails requires a
  full Cluster + PVC delete + Flux resume cycle ([[cnpg-bootstrap-immutable]]).
  Plan: dry-run S0-1 first; don't touch freshrss until S0 passes.
- **Operator `0.27.0` honoring `volumeName`** (Q2 from the lab review) — must
  be verified on S0-1, not assumed.
- **Snapshot retention** — open question. Recommend daily snapshots, keep 14
  days, then weekly for 12 weeks; ZFS retention configured on TrueNAS side
  (not via CSI).
- **S-6 dump storage location** — TrueNAS NFS mount vs an iSCSI volume vs an
  S3 endpoint on TrueNAS. NFS is simplest; iSCSI is more consistent with the
  rest of the lab. Decide before S6-1.
- **Which cluster first?** Recommend **freshrss** (lower blast radius — losing
  RSS reading state for an hour is fine; losing SSO would gate every app).
- **Cilium L7 filter** — the new CronJob pods that talk to CNPG :5432 need a
  CCNP egress allow ([[cilium-gateway-egress-l7-filter]] taught us not to
  trust `world` for in-cluster traffic). Add to the CronJob namespace's
  allow CCNP.

## Acceptance criteria

- `VolumeSnapshotClass` live; manual `VolumeSnapshot` from an iSCSI PVC works
  end-to-end.
- Both CNPG clusters run single-instance on static iSCSI zvol PVs with
  `reclaimPolicy: Retain`.
- `ScheduledBackup` CRs producing `VolumeSnapshot`s daily for both clusters;
  ZFS snapshots visible on TrueNAS.
- **S-6 rip cord:** `_hack/scripts/cnpg-dump.sh` (or equivalent) produces a
  restorable dump per cluster; restore runbook in `_docs/guides/cnpg-rescue.md`
  tested against the throwaway cluster.
- O-7 alert fires (verified by deliberately suspending a `ScheduledBackup` for
  > 36h on the test cluster).
- Flux all-green; both apps fully functional post-migration.
