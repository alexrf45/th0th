# Database rescue — restoring CNPG from a pg_dump backup

> **When to use:** the preferred recovery is a CSI `VolumeSnapshot` restore via
> `bootstrap.recovery.volumeSnapshots`. Use *this* path when that's
> unavailable — snapshot integrity is in doubt, the snapshot-controller is
> broken, or the data dir on the iSCSI zvol is corrupted. It's slower than a
> snapshot restore but independent of the entire CSI stack.

The rip cord is a daily `pg_dump --format=custom` per CNPG cluster, written to a
per-namespace iSCSI PVC by a CronJob in
`_lib/applications/<app>/overlays/dev/dump-cronjob.yaml`. Examples below use the
`freshrss` app; substitute your own namespace, cluster, and PVC names.

## Step 0 — inspect available dumps

Kick a diag pod that mounts the dump PVC:

```sh
kube dev -n freshrss run dump-inspect --rm -i --tty --restart=Never \
  --image=ghcr.io/cloudnative-pg/postgresql:17.4-6 \
  --overrides='{"spec":{"containers":[{"name":"dump-inspect","image":"ghcr.io/cloudnative-pg/postgresql:17.4-6","stdin":true,"tty":true,"volumeMounts":[{"name":"b","mountPath":"/backup"}]}],"volumes":[{"name":"b","persistentVolumeClaim":{"claimName":"dev-freshrss-dumps-pvc"}}]}}' \
  -- bash
```

Verify the newest dump is sane:

```sh
pg_restore --list /backup/freshrss-<UTC-stamp>.dump | head -20
```

## Step 1 — copy the dump off-cluster (recommended)

If you suspect the iSCSI zvol itself is degraded, get a copy onto a workstation
before doing anything else:

```sh
kube dev -n freshrss cp dump-inspect:/backup/freshrss-<stamp>.dump ./freshrss-<stamp>.dump
```

## Logical restore into a fresh CNPG cluster

The cleanest recovery: bootstrap a brand-new cluster via `initdb`, then
`pg_restore` the dump into it.

### 1. Tear down the broken cluster

CNPG bootstrap is one-shot. To rebuild from `initdb` you must delete the existing
`Cluster` **and** its instance PVCs.

```sh
# Suspend Flux so it doesn't immediately recreate what we delete.
k8sop dev flux suspend kustomization freshrss

# Delete the Cluster and its PVCs.
kube dev -n freshrss delete cluster.postgresql.cnpg.io freshrss-dev-cluster
kube dev -n freshrss delete pvc -l cnpg.io/cluster=freshrss-dev-cluster

# On a static iSCSI PV (Retain), the underlying zvol survives. Delete the PV
# by hand only if you explicitly want to wipe it:
#   kube dev delete pv dev-freshrss-db-pv
```

### 2. Resume Flux + let CNPG bootstrap a fresh cluster

```sh
k8sop dev flux resume kustomization freshrss
k8sop dev flux reconcile kustomization freshrss

# Watch it come up: initdb creates the database empty (no app data yet).
kube dev -n freshrss get cluster freshrss-dev-cluster -w
```

Wait until `READY=1 STATUS="Cluster in healthy state"`.

### 3. Restore the dump

```sh
SUPER_SECRET=$(kube dev -n freshrss get cluster freshrss-dev-cluster -o jsonpath='{.spec.superuserSecret.name}')
SUPER_USER=$(kube dev -n freshrss get secret "$SUPER_SECRET" -o jsonpath='{.data.username}' | base64 -d)
SUPER_PASS=$(kube dev -n freshrss get secret "$SUPER_SECRET" -o jsonpath='{.data.password}' | base64 -d)

kube dev -n freshrss run pg-restore --rm -i --restart=Never \
  --image=ghcr.io/cloudnative-pg/postgresql:17.4-6 \
  --env="PGPASSWORD=$SUPER_PASS" \
  --overrides="{\"spec\":{\"containers\":[{\"name\":\"pg-restore\",\"image\":\"ghcr.io/cloudnative-pg/postgresql:17.4-6\",\"env\":[{\"name\":\"PGPASSWORD\",\"value\":\"$SUPER_PASS\"}],\"command\":[\"pg_restore\",\"--host=freshrss-dev-cluster-rw\",\"--port=5432\",\"--username=$SUPER_USER\",\"--dbname=freshrss\",\"--clean\",\"--if-exists\",\"--no-owner\",\"--no-acl\",\"--verbose\",\"/backup/freshrss-<UTC-stamp>.dump\"],\"volumeMounts\":[{\"name\":\"b\",\"mountPath\":\"/backup\"}]}],\"volumes\":[{\"name\":\"b\",\"persistentVolumeClaim\":{\"claimName\":\"dev-freshrss-dumps-pvc\"}}]}}"
```

`--clean --if-exists` drops + recreates schema objects so the restore works
against the `initdb`-empty database. `--no-owner --no-acl` strips ownership and
grant statements, since users created by `initdb` may differ from the original.

### 4. Verify

```sh
kube dev -n freshrss exec -it freshrss-dev-cluster-1 -- \
  psql -U freshrss -d freshrss -c "\dt"
```

Bounce the application pods if they're still connected to the old backend
service IP, then confirm normal operation in the UI.

### 5. Re-verify backups

```sh
# Trigger an immediate VolumeSnapshot via the ScheduledBackup
kube dev -n freshrss annotate scheduledbackup freshrss-dev-cluster-snap \
  cnpg.io/now=$(date -u +%Y-%m-%dT%H:%M:%SZ) --overwrite

# Manual dump run to confirm the rip cord still works
kube dev -n freshrss create job --from=cronjob/freshrss-cnpg-dump cnpg-dump-manual-$(date +%s)
```

## Gotchas

These surfaced in a full restore drill — worth knowing before you need them:

- **Always use `--clean --if-exists`.** Restoring without them onto a non-empty
  database COPYs the dump's *old* rows on top of existing tables (e.g. stale
  feeds reappear) instead of replacing them. Only skip the flags if you've
  already dropped every table the dump touches.
- **`--no-owner --no-acl`** avoids `role "..." does not exist` errors when the
  restored roles differ from the originals.
- **Mirror the source's `postgresql.parameters` on any restore cluster.**
  Database-level settings (e.g. `pgaudit.log`) are preserved in the recovered
  data, so the restore cluster needs the matching `shared_preload_libraries` or
  the first statement errors with `pgaudit must be loaded via shared_preload_libraries`.
- **Network policy is cluster-name-specific.** A `*-cnpg-allow` policy selects by
  `cnpg.io/cluster: <name>`, so a differently-named restore/drill cluster falls
  through to default-deny and the operator can't reach its instance-manager on
  `:8000` (it sticks at "Setting up primary"). Apply a one-shot policy mirroring
  the production rules with the restore cluster's selector.
- **`pg_restore` exits non-zero on any ignored error**, even when the data
  restored correctly. Use `restartPolicy: Never` + `backoffLimit: 0` so the pod
  stays around for log inspection instead of looping into BackOff.
- **VolumeSnapshot restore size has overhead.** A CSI snapshot's `RESTORESIZE`
  can be slightly larger than the source PV (filesystem metadata). Requesting
  exactly the source size fails — bump the restore PVC by ~1 GiB. Check the
  snapshot's `RESTORESIZE` field before applying.
- **NAS-side cleanup is manual.** With `reclaimPolicy: Retain`, deleting Released
  PVs in Kubernetes does **not** remove the underlying iSCSI extents/zvols on the
  NAS — reclaim that space by hand.

## Common failure modes

| Symptom | Likely cause | Action |
| ------- | ------------ | ------ |
| `pg_restore: could not connect to server` | network policy blocks the restore pod | label the pod so the `*-dump-allow` policy picks it up, or run `pg_restore` inside the primary pod (no policy traversal) |
| `relation "..." already exists` | missing `--clean --if-exists` | add the flags and re-run |
| `role "..." does not exist` | missing `--no-owner --no-acl` | add the flags and re-run |
| Dump file is empty / 0 bytes | the CronJob is failing | `kube dev -n <ns> logs job/<latest-cnpg-dump-job>` |
| Cluster won't bootstrap after delete | an instance PVC survived | `kube dev -n <ns> get pvc \| grep <cluster>` and clean up stragglers — one-shot bootstrap needs an empty slate |
