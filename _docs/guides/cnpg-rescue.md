# CNPG rescue — restoring from S-6 pg_dump rip cord

> **When to use:** the VolumeSnapshot-based recovery path (ADR-0003 / sprint
> S-1/S-2) is unavailable — TrueNAS / democratic-csi snapshot integrity is in
> doubt, the snapshot-controller is broken, or the data dir on the iSCSI
> zvol is corrupted. This is the **last-resort** recovery — slower than a
> VolumeSnapshot restore, but independent of the entire CSI stack.

The S-6 rip cord is a daily `pg_dump --format=custom` per CNPG cluster,
written to a per-namespace iSCSI PVC (`dev-<app>-dumps-pvc`) by a CronJob
defined in `_lib/applications/<app>/overlays/dev/dump-cronjob.yaml`.

## Inventory

| Cluster | Namespace | Dump PVC | Dump filename |
| ------- | --------- | -------- | ------------- |
| `freshrss-dev-cluster` | `freshrss` | `dev-freshrss-dumps-pvc` | `freshrss-<UTC-stamp>.dump` |
| `authentik-dev-cluster` | `authentik` | `dev-authentik-dumps-pvc` | `authentik-<UTC-stamp>.dump` |

## Step 0 — inspect available dumps

```sh
kube dev -n freshrss debug -it --image=ghcr.io/cloudnative-pg/postgresql:17.4-6 \
  --target=$(kube dev -n freshrss get pod -l app=cnpg-dump -o name | head -1) \
  -- ls -lh /backup
```

Or just kick a dedicated diag pod that mounts the dump PVC:

```sh
kube dev -n freshrss run dump-inspect --rm -i --tty --restart=Never \
  --image=ghcr.io/cloudnative-pg/postgresql:17.4-6 \
  --overrides='{"spec":{"containers":[{"name":"dump-inspect","image":"ghcr.io/cloudnative-pg/postgresql:17.4-6","stdin":true,"tty":true,"volumeMounts":[{"name":"b","mountPath":"/backup"}]}],"volumes":[{"name":"b","persistentVolumeClaim":{"claimName":"dev-freshrss-dumps-pvc"}}]}}' \
  -- bash
```

Verify the newest dump is sane:

```sh
pg_restore --list /backup/freshrss-20260526T030000Z.dump | head -20
```

## Step 1 — copy the dump off-cluster (optional but recommended)

If you suspect the iSCSI zvol itself is degraded, get a copy onto a
workstation before doing anything else:

```sh
kube dev -n freshrss cp dump-inspect:/backup/freshrss-<stamp>.dump ./freshrss-<stamp>.dump
```

## Path A — logical restore into a fresh CNPG cluster (recommended)

The cleanest recovery: bootstrap a brand-new CNPG cluster via `initdb`,
then `pg_restore` the dump into it.

### A.1 — tear down the broken cluster

CNPG bootstrap is one-shot ([[cnpg-bootstrap-immutable]]). To rebuild
from initdb you must delete the existing `Cluster` AND its instance PVCs.

```sh
# Suspend Flux so it doesn't immediately recreate what we delete.
k8sop dev flux suspend kustomization freshrss

# Delete the Cluster and its PVCs.
kube dev -n freshrss delete cluster.postgresql.cnpg.io freshrss-dev-cluster
kube dev -n freshrss delete pvc -l cnpg.io/cluster=freshrss-dev-cluster

# When the cluster is on a static iSCSI PV (post-S2a) the PV is Retain,
# so the underlying zvol survives. Delete the PV by hand only if you
# explicitly want to wipe it:
#   kube dev delete pv dev-freshrss-db-pv
```

### A.2 — resume Flux + let CNPG bootstrap a fresh cluster

```sh
k8sop dev flux resume kustomization freshrss
k8sop dev flux reconcile kustomization freshrss

# Watch the cluster come up. It will run initdb and create the database
# empty (no application data yet).
kube dev -n freshrss get cluster freshrss-dev-cluster -w
```

Wait until `READY=1 STATUS="Cluster in healthy state"`.

### A.3 — restore the dump

```sh
# Connection details
SUPER_SECRET=$(kube dev -n freshrss get cluster freshrss-dev-cluster -o jsonpath='{.spec.superuserSecret.name}')
SUPER_USER=$(kube dev -n freshrss get secret "$SUPER_SECRET" -o jsonpath='{.data.username}' | base64 -d)
SUPER_PASS=$(kube dev -n freshrss get secret "$SUPER_SECRET" -o jsonpath='{.data.password}' | base64 -d)

# Run pg_restore from a one-shot pod that mounts the dumps PVC.
kube dev -n freshrss run pg-restore --rm -i --restart=Never \
  --image=ghcr.io/cloudnative-pg/postgresql:17.4-6 \
  --env="PGPASSWORD=$SUPER_PASS" \
  --overrides="{\"spec\":{\"containers\":[{\"name\":\"pg-restore\",\"image\":\"ghcr.io/cloudnative-pg/postgresql:17.4-6\",\"env\":[{\"name\":\"PGPASSWORD\",\"value\":\"$SUPER_PASS\"}],\"command\":[\"pg_restore\",\"--host=freshrss-dev-cluster-rw\",\"--port=5432\",\"--username=$SUPER_USER\",\"--dbname=freshrss\",\"--clean\",\"--if-exists\",\"--no-owner\",\"--no-acl\",\"--verbose\",\"/backup/freshrss-<UTC-stamp>.dump\"],\"volumeMounts\":[{\"name\":\"b\",\"mountPath\":\"/backup\"}]}],\"volumes\":[{\"name\":\"b\",\"persistentVolumeClaim\":{\"claimName\":\"dev-freshrss-dumps-pvc\"}}]}}"
```

`--clean --if-exists` drops + recreates schema objects so the restore
works against the initdb-empty database. `--no-owner --no-acl` strips
the ownership and grant statements, since users created by initdb may
differ from the original.

### A.4 — verify

```sh
# Sanity check: row counts in a couple of expected tables
kube dev -n freshrss exec -it freshrss-dev-cluster-1 -- \
  psql -U freshrss -d freshrss -c "\dt"
```

Bounce the application pods if they're still connected to the old
(now-dead) backend service IP, and confirm normal operation in the UI.

### A.5 — re-verify backups

```sh
# Trigger an immediate VolumeSnapshot via the ScheduledBackup
kube dev -n freshrss annotate scheduledbackup freshrss-dev-cluster-snap \
  cnpg.io/now=$(date -u +%Y-%m-%dT%H:%M:%SZ) --overwrite

# Manual dump run to confirm S-6 still works
kube dev -n freshrss create job --from=cronjob/freshrss-cnpg-dump cnpg-dump-manual-$(date +%s)
```

## Path B — physical restore from a basebackup (when we add it)

> **Not implemented as of this sprint.** Current S-6 dumps are
> `pg_dump --format=custom` only. If we add `pg_basebackup` to the
> CronJob later, this section will cover `bootstrap.recovery.backup`
> against a Volume populated from the basebackup.

## Common failure modes

| Symptom | Likely cause | Action |
| ------- | ------------ | ------ |
| `pg_restore: error: could not connect to server` | CCNP egress missing on the restore pod | Ensure `app: cnpg-dump` label on the pod so `<app>-dump-allow` CCNP picks it up, OR run `pg_restore` directly inside the primary pod (no network policy traversal). |
| `pg_restore: error: relation "..." already exists` | Forgot `--clean --if-exists` | Add the flags and re-run. |
| `pg_restore: error: role "..." does not exist` | Forgot `--no-owner --no-acl` | Add the flags and re-run. |
| Dump file is empty / 0 bytes | The CronJob is failing | Check `kube dev -n <ns> logs job/<latest-cnpg-dump-job>`; the script bails if the dump is `<1024` bytes. |
| Cluster won't bootstrap after delete | One of the instance PVCs survived | `kube dev -n <ns> get pvc | grep <cluster>` and clean up stragglers. CNPG one-shot bootstrap requires an empty slate ([[cnpg-bootstrap-immutable]]). |

## Drill log — 2026-05-28

First end-to-end exercise of both rip cords against `freshrss-dev-cluster`. The
source cluster was never touched; everything ran in a throwaway
`freshrss-drill-cluster` in the `freshrss` namespace. Both paths **PASSED**
once the gotchas below were worked around.

### Path A — VolumeSnapshot clone via `bootstrap.recovery.volumeSnapshots`

| | |
| --- | --- |
| Source snapshot | `freshrss-dev-cluster-snap-20260528040000` (RESTORESIZE `10485776Ki`) |
| Drill `storage.size` | `11Gi` — see gotcha #1 |
| Time to `Cluster in healthy state` | ~80 s |
| Row counts (source vs drill) | identical: `category=11`, `feed=43`, `entry=6874`, `tag=0` |
| Result | **PASS** |

### Path B — `pg_restore` from S-6 dump

| | |
| --- | --- |
| Dump | `freshrss-20260528T030011Z.dump` (54 KiB, 03:00 UTC) |
| Restore Job | `app=cnpg-restore` mounting `dev-freshrss-dumps-pvc`, connecting to `freshrss-drill-cluster-rw` over network |
| Test perturbation | `DROP TABLE freshrss_fr3d_entry CASCADE;` |
| Flags | `--clean --if-exists --no-owner --no-acl` (see gotcha #2) |
| Errors after `--clean --if-exists` | 2 (benign — `must be owner of extension pgaudit`, harmless since the extension is already loaded) |
| Row counts after restore | `category=3`, `feed=30`, `entry=248`, `tag=0` — exactly matches the dump's captured state |
| Result | **PASS** |

The dump's snapshot is from 03:00 UTC, and the freshrss feed-actualize burst happened between 03:00 and 04:00 UTC, so the S-6 dump is meaningfully behind the VolumeSnapshot (248 entries vs 6874). Worth noting for RPO planning: **the S-6 dump's worst-case RPO is ~24h, but its in-window staleness can be material if the source is actively ingesting.** The primary VolumeSnapshot path is preferred whenever it's available.

### Gotchas surfaced

1. **VolumeSnapshot restore size overhead.** democratic-csi's VolumeSnapshot reports `RESTORESIZE` slightly larger than the source PV (`10485776 KiB` for a 10Gi source — ~16 KiB of TrueNAS metadata). Requesting `storage.size: 10Gi` on the drill Cluster fails with `requested volume size 10737418240 is less than the size 10737434624 for the source snapshot`. **Bump the drill PVC by ~1 GiB** (`11Gi` works). Confirmed in the runbook's Path A by inspecting the snapshot's `RESTORESIZE` field before applying.
2. **`pg_restore` without `--clean --if-exists` corrupts not-dropped tables.** First attempt restored from the dump without those flags after dropping only `entry`. Result: 36 ignored errors, plus the dump's *old* `feed` rows were COPYed onto the post-OPML-import feed table (43 → 73 rows; 30 stale CSHub-era feeds reappeared from the dump). **Always use `--clean --if-exists`** unless you've already dropped every table the dump touches.
3. **`bootstrap.recovery` does not carry `postgresql.parameters`.** The source `freshrss-dev-cluster` has `pgaudit.log = 'all, -misc'` set, and that database-level setting is preserved in the recovered data. Without a matching `postgresql.parameters` block on the drill Cluster spec, pgaudit isn't loaded in `shared_preload_libraries`, and the first statement against the restored DB errors with `pgaudit must be loaded via shared_preload_libraries`. **Mirror the source's `postgresql.parameters` on any drill/restore cluster.**
4. **CCNPs are cluster-name-specific.** `freshrss-cnpg-allow` selects `cnpg.io/cluster: freshrss-${ENVIRONMENT}-cluster`, so the drill cluster's pods fall through to `freshrss-default-deny`. The CNPG operator can't reach the drill instance-manager on `:8000` and the cluster sticks at "Setting up primary". **Either name the drill cluster the same as production (won't fly — the names must differ) or apply a one-shot CCNP that mirrors the production rules with the drill cluster's selector.** This drill applied `freshrss-drill-cluster-allow` for that purpose.
5. **`pg_restore` exit code is non-zero on any ignored error**, even when the data restore is correct (warning lines like "errors ignored on restore: 2" still exit 1). `restartPolicy: Never` + `backoffLimit: 0` on the restore Job keeps the pod around so the operator can inspect logs and decide; `OnFailure` would otherwise loop and BackOff before logs are reachable.
6. **TrueNAS-side cleanup is manual.** With `reclaimPolicy: Retain` on the iscsi SC (the post-S4 default), deleting the Released PVs in k8s does NOT remove the underlying iSCSI extents/zvols on TrueNAS. After this drill, three ~11 GiB drill zvols (`pvc-538ff539-…`, `pvc-db9d85d3-…`, `pvc-e7fec3ea-…`) remain on TrueNAS and need hand-deletion to fully reclaim space.

## See also

- ADR-0003 — `_docs/decisions/0003-cnpg-local-snapshots.md`
- Storage sprint — `_docs/storage-sprint.md`
- Memory note: `[[cnpg-bootstrap-immutable]]`
