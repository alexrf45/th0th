# App guide: Authentik (SSO / IdP)

**Role:** Cluster-wide identity provider. Fronts apps with OIDC (native) or forward-auth (outposts).
**Status:** Live on dev (`memphis`) since 2026-05-20. Internal-only at `dev.int.auth.home-0ps.com`.
**Design rationale:** [ADR-0001](../decisions/0001-sso-authentik.md). Recovery: §[Recovery](#recovery-and-day-2). Consumer example: [Grafana OIDC](#wiring-an-oidc-consumer-grafana-pattern).

---

## At a glance

| | |
| --- | --- |
| Chart | `authentik` `2026.2.3` (`https://charts.goauthentik.io`) |
| Components | server + worker (no Redis — Postgres is broker+cache in 2026.x) |
| Database | CNPG `authentik-dev-cluster`, 3 instances, local-path (5Gi data + 2Gi WAL each) |
| Backup | Barman → Cloudflare R2 (`dev-authentik-e53522c0`) — slated to move to CSI snapshots per [ADR-0003](../decisions/0003-cnpg-local-snapshots.md) |
| Secrets | `authentik-env` + `authentik-r2-creds` via ESO ← 1Password |
| Ingress | HTTPRoute on the Cilium Gateway; TLS via the `wildcard-tls` SAN cert |
| Flux Kustomization | `authentik` (top-level, in `_clusters/dev/cluster.yaml`) |

## Where it lives

| Path | What |
| --- | --- |
| `_lib/controllers/authentik/` | Helm chart (server+worker), `helmrelease.yaml` pins `2026.2.3`, `existingSecret: authentik-env`, `postgresql.enabled: false`, `geoip/ingress/serviceMonitor: false`, `nodeSelector: {node: worker}`, `blueprints.configMaps` + `global.envFrom` for the Grafana OIDC blueprint |
| `_lib/applications/authentik/base/external-secret.yaml` | ESO refs producing `authentik-env` (chart + CNPG) and `authentik-r2-creds` (Barman) |
| `_lib/applications/authentik/base/external-secret-grafana-oidc.yaml` | ESO ref producing `authentik-grafana-oidc` (`GRAFANA_OIDC_CLIENT_ID`/`_SECRET`) from 1P `grafana_oidc_${ENVIRONMENT}` — the **same** item Grafana reads |
| `_lib/applications/authentik/base/blueprint-grafana.yaml` | ConfigMap `authentik-grafana-blueprint`: the Grafana OIDC blueprint (provider + application + entitlements + admin binding) |
| `_lib/applications/authentik/base/httproute.yaml` | `${AUTHENTIK_SUBDOMAIN}.home-0ps.com` → server :9000 |
| `_lib/applications/authentik/overlays/dev/database.yaml` | CNPG `Cluster` + `ScheduledBackup` |
| `_lib/applications/authentik/overlays/dev/ob-archiver.enc.yaml` | SOPS-encrypted Barman `ObjectStore` (R2). **No `ob-recovery` in dev** — deferred to prod (see Recovery §3) |
| `_lib/security/cilium-network-policies/authentik-{default-deny,allow,cnpg-allow}.yaml` | Network policy: default-deny + ingress from `reserved:ingress` on 9000 + CNPG operator allow |
| `_clusters/dev/config/cluster-configs.yaml` | `AUTHENTIK_SUBDOMAIN: "dev.int.auth"` |

## How it's deployed

The chart is installed by the `controllers` Flux Kustomization; the app (DB, ESO, HTTPRoute, Barman) by the top-level `authentik` Kustomization, which `dependsOn` controllers, dns, storage, networking, external-secrets-operator, secrets, security.

**Bootstrap ordering gotcha:** the chart consumes `authentik.existingSecret.secretName: authentik-env` and (via `global.envFrom`) `authentik-grafana-oidc`. Both secrets are produced by ExternalSecrets in the **applications** layer, one layer *after* the chart installs — so on a fresh bootstrap server+worker pods `CreateContainerConfigError`/CrashLoop with `secret not found` until ESO syncs them, then self-heal. The `controllers` Kustomization has `wait: true` but waits for HelmRelease `Released`, not pod readiness, so this does **not** block downstream layers. (Worker boots with the OIDC env vars present, so the Grafana blueprint applies with the correct client creds on first start — see [OIDC consumers](#wiring-an-oidc-consumer-grafana-blueprint).)

## Secrets

One 1Password item `authentik_${ENVIRONMENT}` (HomeLab vault) feeds a single `ExternalSecret` that emits both CNPG-shape and chart-shape keys (CNPG ignores the extra keys):

| 1P field | K8s key(s) | Used by |
| --- | --- | --- |
| `username` / `password` | `username`/`password` + `AUTHENTIK_POSTGRESQL__USER`/`__PASSWORD` | CNPG bootstrap + chart |
| `database` | `AUTHENTIK_POSTGRESQL__NAME` (`authentik`) | chart |
| `host`/`port` | `AUTHENTIK_POSTGRESQL__HOST`/`__PORT` (`authentik-dev-cluster-rw.authentik.svc`:`5432`) | chart (can be hardcoded in the ES template — no secret content) |
| `secret_key` | `AUTHENTIK_SECRET_KEY` | chart — **60+ random chars, NEVER change after install** (cookie signing + user IDs) |
| `bootstrap_email` / `bootstrap_password` / `bootstrap_token` | `AUTHENTIK_BOOTSTRAP_*` | local-admin (`akadmin`) recovery — never federated |

`authentik-r2-creds` (created by Terraform) carries `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`/`AWS_ENDPOINT_URL`/`AWS_REGION`/`BUCKET_NAME`/`EXPIRES_ON` for Barman.

A second ExternalSecret, `authentik-grafana-oidc`, pulls the Grafana OIDC client credentials from the **shared** 1Password item `grafana_oidc_${ENVIRONMENT}` (the same item Grafana's own `grafana-oidc` ExternalSecret reads) and exposes them to the pods as env vars (`GRAFANA_OIDC_CLIENT_ID`/`_SECRET`) for the blueprint to consume. See [OIDC consumers](#wiring-an-oidc-consumer-grafana-blueprint) for the item format.

> Per the project rule, ObjectStore manifests are written plaintext and **you** SOPS-encrypt them (`--encrypted-regex '^(data|destinationPath|endpointURL)$'`). Never re-encrypt secrets without confirmation.

## Wiring an OIDC consumer (Grafana blueprint)

The Grafana integration is **config-as-code** via an [Authentik blueprint](https://docs.goauthentik.io/docs/customize/blueprints/) — a fresh cluster comes up with the provider, application, entitlements, and admin role binding already created, no UI clicks. Roles map via **per-app entitlements**, not groups (the `groups` property mapping isn't shipped in 2026.x; `profile` already carries group membership; entitlements are per-app and more granular).

**How it works**

- `blueprint-grafana.yaml` defines a ConfigMap (`authentik-grafana-blueprint`) the chart mounts under `/blueprints` via `blueprints.configMaps`; the **worker** auto-discovers and applies any `*.yaml` there on an interval.
- The blueprint declares: an `oauth2provider` (confidential, strict redirect `https://${GRAFANA_SUBDOMAIN}.home-0ps.com/login/generic_oauth`, scopes `openid email profile entitlements offline_access`, signed by the default self-signed cert), an `application` (slug `grafana`) bound to it, three `applicationentitlement`s (`Grafana Admins`/`Editors`/`Viewers` — names must match Grafana's `role_attribute_path` JMESPath *exactly*), and a `policybinding` granting the built-in `authentik Admins` group the `Grafana Admins` entitlement so superusers get Admin on first login. Everyone else falls through to Viewer.
- `client_id`/`client_secret` are **set** by the blueprint via `!Env` (`GRAFANA_OIDC_CLIENT_ID`/`_SECRET`), loaded from the `authentik-grafana-oidc` secret. Because that secret and Grafana's `grafana-oidc` secret read the **same** 1Password item, both ends of the handshake stay in lockstep with one source of truth.

> **Adoption vs. duplicate:** the blueprint matches existing objects by their `identifiers` (provider `name: grafana`, app `slug: grafana`, entitlement `name` + app). If a provider/app with those exact identifiers already exists it is **updated in place**; differently-named manual objects would produce a parallel set. On a fresh-DB cluster (dev does `initdb`, not recovery) there are none, so it always creates clean.

### 1Password item format (`grafana_oidc_${ENVIRONMENT}`)

One item in the **HomeLab** vault, titled `grafana_oidc_dev` (pattern `grafana_oidc_<env>`), with two fields. Authentik no longer *generates* these — you own them, and the blueprint applies them to the provider:

| 1P field | K8s key (both ES) | Format / how to generate |
| --- | --- | --- |
| `client_id` | `client_id` | URL-safe public identifier. `openssl rand -hex 20` (40 chars) |
| `client_secret` | `client_secret` | High-entropy, treat as a password. `openssl rand -hex 64` (128 chars) |

Both Authentik (`authentik-grafana-oidc`, authentik ns) and Grafana (`grafana-oidc`, monitoring ns) ExternalSecrets reference this one item, so set it **before** bootstrap. Values are arbitrary strings — any matching pair works; they only need to be identical on both sides.

**Rotation:** change the field(s) in 1Password → ESO resyncs both secrets. Authentik reads them via `!Env` at pod start, so **bounce the Authentik server+worker** (`kube dev -n authentik rollout restart deploy/authentik-server deploy/authentik-worker`) and restart Grafana to complete the rotation.

**Adding another OIDC consumer:** copy `blueprint-grafana.yaml` + `external-secret-grafana-oidc.yaml`, swap names/scopes/redirect, add the new ConfigMap to `blueprints.configMaps` and a `global.envFrom` entry for the new secret. The legacy UI walkthrough is archived at `archive/source-docs/grafana-oidc-setup.md`.

## Recovery and day-2

Full runbook: archived `archive/source-docs/authentik-recovery-runbook.md`. Highlights:

- **Local-admin break-glass:** `akadmin` is never federated. Log in directly at `/if/flow/default-authentication-flow/` (skip a broken brand redirect) with `bootstrap_password` from 1P; admin UI at `/if/admin/`. If the flow itself is broken, hit the API with `bootstrap_token`. Rotate `bootstrap_password` after any observed login.
- **R2 token rotation** (180-day TTL; watch `EXPIRES_ON`): `terraform apply -target=...cloudflare_api_token.r2_bucket[0] -target=...onepassword_item.r2_creds[0]` in `terraform/dev/authentik-object-storage`; ESO resyncs; bounce the CNPG primary to pick it up immediately.
- **CNPG restore from R2:** dev ships **no** recovery ObjectStore — you'd create one on the spot. CNPG bootstrap is one-shot/immutable: suspend the `authentik` Flux Kustomization, delete the `Cluster` + instance PVCs, switch `database.yaml` to `bootstrap.recovery`, resume, then revert to `initdb` in a follow-up commit.

## Troubleshooting

| Symptom | First check | Likely fix |
| --- | --- | --- |
| Pods CrashLoop `secret not found` | `kube dev -n authentik get externalsecret` | 1P item missing fields / ESO not synced — `describe externalsecret authentik-env` |
| Login flow 500 | server pod logs | custom flow with a missing stage — log in as `akadmin` via default flow URL, inspect bindings |
| Backups not landing in R2 | CNPG primary Barman sidecar logs | token expired (`EXPIRES_ON`) — rotate |
| `dev.int.auth...` NXDOMAIN | ExternalDNS logs / [infra/dns.md](../infra/dns.md) | confirm HTTPRoute + the in-cluster CoreDNS split-horizon forward |
| TLS handshake fails | `describe cert wildcard-tls` | SAN missing — the `*.home-0ps.com` wildcard does **not** cover three-label hosts; the SAN must be explicit |
| Every OIDC user lands as Viewer | provider Selected Scopes + entitlement names | `entitlements` scope missing, name mismatch vs JMESPath, or user not bound |

## Known gotchas & follow-ups

- Authentik 2026.x is **Redis-less** — ignore older docs.
- The wildcard SAN cert covers `dev.int.auth` explicitly (three-label host); don't rely on the wildcard.
- `serviceMonitor.enabled: false` — no metrics/dashboards yet (observability follow-up O-9).
- Public exposure (Cloudflare Tunnel + forward-auth outposts) and the CF WAF rule are future phases, not built.
- DB will migrate to single-instance static iSCSI + CSI snapshots per [ADR-0003](../decisions/0003-cnpg-local-snapshots.md).
