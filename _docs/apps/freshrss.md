# FreshRSS (RSS / Atom aggregator)

A self-hosted feed reader. The interesting part for the lab is the
**non-root-app-with-a-root-assuming-entrypoint** hardening pattern — reusable for
any image that wants to run as root but shouldn't.

> **Example values.** `freshrss.int.lab.example.com` and 1Password item names
> are placeholders.

## At a glance

| | |
| --- | --- |
| Image | `freshrss/freshrss:${FRESHRSS_VERSION}` |
| Topology | 1 replica, `strategy: Recreate` (RWO data volume) |
| App data | static iSCSI PV (`Retain`) — the [static-volume pattern](../infra/storage.md#provision-a-static-iscsi-volume) |
| Database | CloudNativePG cluster, single-instance on static iSCSI, PG 17.x, pgaudit on |
| Secrets | `freshrss-db-creds` via External Secrets ← 1Password |
| Ingress | `HTTPRoute` `${FRESHRSS_SUBDOMAIN}.lab.example.com` → :80 |
| Flux Kustomization | `freshrss` (top-level) |

## Where it lives

| Path | What |
| --- | --- |
| `_lib/applications/freshrss/base/deployment.yaml` | init-container + main container (hardening below) |
| `_lib/applications/freshrss/base/secrets.yaml` | `freshrss-db-creds` ExternalSecret |
| `_lib/applications/freshrss/base/init-script-configmap.yaml` | custom `bootstrap.sh` mounted at `/opt/freshrss-init` |
| `_lib/applications/freshrss/overlays/dev/volume.yaml` | static iSCSI PV+PVC (the active data volume) |
| `_lib/applications/freshrss/overlays/dev/database.yaml` | CNPG `Cluster` |
| `_lib/security/cilium-network-policies/freshrss-{default-deny,allow,cnpg-allow}.yaml` | network policy |

## The securityContext / writable-paths pattern

FreshRSS's Alpine entrypoint expects to run as root (it writes
`/etc/php84/php.ini` and seeds a `Docker/` dir), but the main container runs as
**apache (UID 100, GID 82)**. The fix enumerates *every* writable path in one
pass — the general technique for hardening any such image:

- An **init container** runs as root with only `CHOWN`/`DAC_OVERRIDE`/`FOWNER`
  (and `readOnlyRootFilesystem: true`). It copies `/etc/php84` and the `Docker/`
  dir into `emptyDir`s, `chown`s them `100:82`, and pre-`chown`s the persistent
  data volume so the unprivileged main container can write it.
- The **main container** runs `runAsUser: 100`, `runAsGroup: 82`, `fsGroup: 82`,
  drops ALL caps, adds only `NET_BIND_SERVICE`, seccomp `RuntimeDefault`.
- Writable mounts are explicit `emptyDir`s: `/etc/php84`,
  `/var/www/FreshRSS/Docker`, `/var/www/FreshRSS/extensions`, `/tmp`, `/run`;
  plus the data PVC at `/var/www/FreshRSS/data`.

See [Best practices](../guides/best-practices.md#permissions--writable-paths).

## Config & secrets

DB + admin credentials come from one 1Password item → a `freshrss-db-creds`
Secret, injected as env (`DB_HOST/BASE/USER/PASSWORD`, `ADMIN_USER/PASSWORD/EMAIL`).
Probes hit `/i/?c=index&a=index` (liveness 30s delay, readiness 10s).

> **Gotcha — credentials persist to `config.php`.** FreshRSS only reads the DB
> env vars at *install*; after that it writes them into `config.php` on the data
> volume. Rotating the DB password therefore needs an explicit `config.php` patch
> (read `$_ENV` via `php -r`), not just an env change.

## Day-2 / operations

- **Upgrades:** bump `FRESHRSS_VERSION` (Renovate-driven); Flux reconciles,
  `Recreate` swaps the pod.
- **Restart:** `kube dev -n freshrss rollout restart deploy/freshrss`.
- **DB status:** `k8sop dev kubectl-cnpg status <cluster> -n freshrss`.

## Troubleshooting

| Symptom | First check | Likely fix |
| --- | --- | --- |
| Pod stuck `Init` | init-container logs | data PVC unbound or wrong ownership — confirm the PVC is `Bound` |
| 500 / DB errors | `freshrss-db-creds` synced? CNPG healthy? | `get externalsecret -n freshrss`; `kubectl-cnpg status` |
| New pod hangs on rollout | RWO volume held by old pod | `Recreate` strategy is set; if stuck, delete the old pod |
| NXDOMAIN on hostname | ExternalDNS + CoreDNS split-horizon | see [DNS](../infra/dns.md) |

To add **native OIDC** later, the provider/application/entitlement pattern from
[Authentik](authentik.md#wiring-an-oidc-consumer) applies directly (FreshRSS OIDC
via `OIDC_*` env vars).
