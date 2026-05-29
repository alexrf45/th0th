# Authentik (SSO / Identity Provider)

A cluster-wide identity provider that fronts apps with OIDC (native) or
forward-auth (outposts). This guide covers deploying it, wiring an OIDC consumer
as config-as-code, and day-2 recovery.

> **Example values.** `auth.int.lab.example.com`, the `homelab-authentik-backup`
> bucket, and 1Password item names are placeholders.

## At a glance

| | |
| --- | --- |
| Chart | `authentik` `2026.2.3` (`https://charts.goauthentik.io`) |
| Components | server + worker (no Redis — Postgres is broker + cache in 2026.x) |
| Database | CloudNativePG cluster, single-instance on static iSCSI ([Storage](../infra/storage.md)) |
| Backup | CSI `VolumeSnapshot`s |
| Secrets | `authentik-env` (+ OIDC client) via External Secrets ← 1Password |
| Ingress | `HTTPRoute` on the Cilium Gateway; TLS via the `wildcard-tls` SAN cert |
| Flux Kustomization | `authentik` (top-level) |

## Where it lives

| Path | What |
| --- | --- |
| `_lib/controllers/authentik/` | Helm chart (server+worker); `helmrelease.yaml` pins the version, `existingSecret: authentik-env`, `postgresql.enabled: false`, mounts the OIDC blueprint via `blueprints.configMaps` + `global.envFrom` |
| `_lib/applications/authentik/base/external-secret.yaml` | ESO refs producing `authentik-env` (chart + CNPG) |
| `_lib/applications/authentik/base/external-secret-grafana-oidc.yaml` | ESO ref producing the OIDC client creds — the **same** item the consumer reads |
| `_lib/applications/authentik/base/blueprint-grafana.yaml` | ConfigMap: the OIDC blueprint (provider + application + entitlements + admin binding) |
| `_lib/applications/authentik/base/httproute.yaml` | `${AUTHENTIK_SUBDOMAIN}.lab.example.com` → server :9000 |
| `_lib/applications/authentik/overlays/dev/database.yaml` | CNPG `Cluster` + `ScheduledBackup` |
| `_lib/security/cilium-network-policies/authentik-{default-deny,allow,cnpg-allow}.yaml` | default-deny + ingress from `reserved:ingress` on 9000 + CNPG operator allow |

## How it's deployed

The chart is installed by the `controllers` Flux Kustomization; the app (DB,
ESO, HTTPRoute, backups) by the top-level `authentik` Kustomization, which
`dependsOn` controllers, dns, storage, networking, external-secrets-operator,
secrets, and security.

**Bootstrap ordering gotcha:** the chart consumes secrets (`authentik-env`, and
via `global.envFrom` the OIDC client secret) that are produced by
ExternalSecrets in the **applications** layer — one layer *after* the chart
installs. On a fresh bootstrap the server/worker pods `CreateContainerConfigError`
or CrashLoop with `secret not found` until ESO syncs them, then self-heal. The
`controllers` Kustomization's `wait: true` waits for the HelmRelease to be
`Released`, not for pod readiness, so this does **not** block downstream layers.

## Secrets

One 1Password item feeds a single `ExternalSecret` that emits both CNPG-shape and
chart-shape keys (CNPG ignores the extras):

| 1P field | K8s key(s) | Used by |
| --- | --- | --- |
| `username` / `password` | `username`/`password` + `AUTHENTIK_POSTGRESQL__USER`/`__PASSWORD` | CNPG bootstrap + chart |
| `database` | `AUTHENTIK_POSTGRESQL__NAME` | chart |
| `host`/`port` | `AUTHENTIK_POSTGRESQL__HOST`/`__PORT` | chart |
| `secret_key` | `AUTHENTIK_SECRET_KEY` | chart — **60+ random chars, NEVER change after install** (cookie signing + user IDs) |
| `bootstrap_email` / `bootstrap_password` / `bootstrap_token` | `AUTHENTIK_BOOTSTRAP_*` | local-admin recovery — never federated |

## Wiring an OIDC consumer

The cleanest way to integrate a consumer (Grafana is the worked example) is
**config-as-code** via an [Authentik blueprint](https://docs.goauthentik.io/docs/customize/blueprints/):
a fresh cluster comes up with the provider, application, entitlements, and admin
role binding already created — no UI clicks. Roles map via **per-app
entitlements**, not groups (the `groups` property mapping isn't shipped in
2026.x; entitlements are per-app and more granular).

**How it works**

- The blueprint ConfigMap is mounted under `/blueprints` via
  `blueprints.configMaps`; the **worker** auto-discovers and applies any
  `*.yaml` there on an interval.
- It declares: an `oauth2provider` (confidential, strict redirect to the
  consumer's `/login/generic_oauth`, scopes `openid email profile entitlements
  offline_access`), an `application` bound to it, three `applicationentitlement`s
  (names must match the consumer's `role_attribute_path` JMESPath *exactly*), and
  a `policybinding` granting the built-in `authentik Admins` group the admin
  entitlement so superusers get admin on first login. Everyone else falls through
  to the lowest role.
- `client_id`/`client_secret` are set by the blueprint via `!Env`, loaded from a
  Secret. Because that Secret and the consumer's own secret read the **same**
  1Password item, both ends of the handshake stay in lockstep with one source of
  truth.

> **Adoption vs. duplicate:** the blueprint matches existing objects by their
> `identifiers` (provider name, app slug, entitlement name). Matching objects are
> **updated in place**; differently-named manual objects produce a parallel set.
> On a fresh-DB cluster (`initdb`, not recovery) there are none, so it always
> creates clean.

### OIDC client item format

Keep one 1Password item with two fields. Authentik no longer *generates* these —
you own them, and the blueprint applies them to the provider:

| field | how to generate |
| --- | --- |
| `client_id` | URL-safe public identifier — `openssl rand -hex 20` |
| `client_secret` | high-entropy secret — `openssl rand -hex 64` |

Both the Authentik-side and consumer-side ExternalSecrets reference this one
item, so set it **before** bootstrap. Any matching pair works; the values only
need to be identical on both sides.

**Rotation:** change the field(s) in 1Password → ESO resyncs both secrets.
Authentik reads them via `!Env` at pod start, so **bounce server + worker**
(`kube dev -n authentik rollout restart deploy/authentik-server deploy/authentik-worker`)
and restart the consumer to finish.

**Adding another consumer:** copy the blueprint + its ExternalSecret, swap
names/scopes/redirect, add the new ConfigMap to `blueprints.configMaps` and a
`global.envFrom` entry for the new secret.

## Recovery and day-2

- **Local-admin break-glass:** the bootstrap admin is never federated. Log in
  directly at `/if/flow/default-authentication-flow/` (skipping any broken brand
  redirect) with `bootstrap_password` from 1Password; admin UI at `/if/admin/`.
  If the flow itself is broken, hit the API with `bootstrap_token`. Rotate
  `bootstrap_password` after any observed login.
- **CNPG restore:** CNPG bootstrap is one-shot/immutable. To restore, suspend the
  `authentik` Flux Kustomization, delete the `Cluster` + instance PVCs, switch
  `database.yaml` to `bootstrap.recovery`, resume, then revert to `initdb` in a
  follow-up commit. See [Database rescue](../guides/cnpg-rescue.md).

## Troubleshooting

| Symptom | First check | Likely fix |
| --- | --- | --- |
| Pods CrashLoop `secret not found` | `kube dev -n authentik get externalsecret` | 1P item missing fields / ESO not synced — `describe externalsecret authentik-env` |
| Login flow 500 | server pod logs | custom flow with a missing stage — log in as the bootstrap admin via the default flow URL, inspect bindings |
| Hostname NXDOMAIN | ExternalDNS logs / [DNS](../infra/dns.md) | confirm the HTTPRoute + the CoreDNS split-horizon forward |
| TLS handshake fails | `describe cert wildcard-tls` | SAN missing — a `*.lab.example.com` wildcard does **not** cover three-label hosts; add the explicit SAN |
| Every OIDC user lands as the lowest role | provider Selected Scopes + entitlement names | `entitlements` scope missing, name mismatch vs JMESPath, or user not bound |

> **Note:** Authentik 2026.x is **Redis-less** — ignore older docs that wire a
> separate Redis. A `*.lab.example.com` wildcard cert must carry the
> three-label host as an explicit SAN; don't rely on the wildcard.
