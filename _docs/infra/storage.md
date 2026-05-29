# Storage

How the lab provides persistent storage: NAS-backed iSCSI block storage through
a CSI driver, node-local paths for scratch data, and CSI `VolumeSnapshot`s for
database durability.

> **Example values.** Addresses, hostnames, and pool names below are
> placeholders (`10.10.20.0/24`, `lab.example.com`, `tank`, …). Substitute your
> own. The design — not the literals — is what transfers.

## Prerequisites

- A ZFS NAS (this lab uses TrueNAS Scale) reachable on the LAN — e.g.
  `10.10.20.10` — with the iSCSI service enabled and a pool (here: `tank`).
- The `secrets` layer working: the CSI driver reads its NAS API credentials from
  a Kubernetes Secret synced by External Secrets, so `storage` depends on it.

## What you deploy

| Component | Path | Role |
| --- | --- | --- |
| democratic-csi (`freenas-iscsi`) | `_lib/storage/freenas-csi/` | iSCSI CSI driver — dynamic + static PVs against the NAS (`driver: freenas-api-iscsi`, portal `10.10.20.10:3260`, creds via ESO) |
| local-path-provisioner | `_lib/storage/local-path/` | node-local hostpath for scratch / non-critical data |

StorageClass parameters come from the `cluster-config` ConfigMap so they stay
environment-agnostic:

```yaml
STORAGE_CLASS_NAME: iscsi
DATASET_PARENT: tank/iscsi/k8s/volumes
DATASET_SNAPSHOTS: tank/iscsi/k8s/snapshots
RECLAIM_POLICY: "Retain"   # keep volumes if a PVC is deleted by accident
```

## Provision a static iSCSI volume

The reference pattern for any stateful workload that must survive a full
teardown — pre-create the backing zvol, then pin a static PV/PVC to it.

1. **Create a zvol** on the NAS under your volumes dataset
   (`tank/iscsi/k8s/volumes/<name>`).
2. **Define a static PV** and check it into the app overlay
   (reference: `_lib/applications/freshrss/overlays/dev/volume.yaml`):
   - `storageClassName: iscsi`
   - `persistentVolumeReclaimPolicy: Retain`
   - `csi.driver: freenas-api-iscsi`
   - `volumeHandle` = the zvol name
   - `iqn: iqn.2005-10.org.freenas.ctl:<name>`
   - `portal: 10.10.20.10:3260`
3. **Bind it** from the PVC with `volumeName: <pv>` for an explicit, stable bind.

## Database storage (CNPG)

Run PostgreSQL clusters (CloudNativePG) **single-instance on a static iSCSI
zvol** — one zvol per database, bound via `pvcTemplate.volumeName` — with
durability provided by CSI `VolumeSnapshot`s rather than streaming replicas. The
NAS's own ZFS redundancy is the underlying durability layer. For a
single-operator lab this beats node-local paths, which don't survive a node loss.

To enable scheduled snapshots you need, in order: the `external-snapshotter`
CRDs (in `global/crds/`), the snapshot-controller and CSI snapshotter sidecar
(in the `storage` layer), and a `VolumeSnapshotClass`. Verify a *manual*
snapshot succeeds before wiring `ScheduledBackup`.

## Gotchas

- **CNPG bootstrap is one-shot / immutable.** To retry a failed recovery:
  suspend Flux, delete the `Cluster` + its instance PVCs, resume. CNPG does
  **not** garbage-collect instance PVCs on cluster deletion — that's what makes
  the soft-teardown / re-adopt loop possible.
- **CNPG recovery archiver path:** when promoting or restoring on object
  storage, the archiver `destinationPath` must point at a *new, empty* prefix;
  recovery reads from the *old* prefix. Pointing both at the same prefix
  corrupts the archive.
- **Don't retire your only backup before the replacement is proven.** Stand up
  and test snapshots before dropping any pre-existing object-storage backup.
