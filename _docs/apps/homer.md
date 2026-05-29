# Homer (dashboard)

A static, stateless landing-page dashboard for your lab services — config is a
single YAML file, no database, no secrets. It's the simplest app to ship first,
and a clean template for a fully `restricted`-PSA-compliant pod.

> **Example values.** `homer.int.lab.example.com` is a placeholder.

## At a glance

| | |
| --- | --- |
| Image | `b4bz/homer:${HOMER_VERSION}` — ~50 MB Alpine + nginx |
| Topology | 1 replica, `strategy: Recreate`; no DB, no PVC, no secrets |
| Config | a ConfigMap (`homer-config`) mounted at `/www/assets/config.yml` |
| Ingress | `HTTPRoute` `${HOMER_SUBDOMAIN}.lab.example.com` → :8080 |
| Flux Kustomization | `homer` (top-level; `dependsOn` dns, networking, security only) |
| Notable | a good first app for a `restricted` PSA + per-container resource limits |

## Where it lives

| Path | What |
| --- | --- |
| `_lib/applications/homer/base/deployment.yaml` | single container, hardened securityContext |
| `_lib/applications/homer/base/configmap.yaml` | `config.yml` — the entire dashboard state |
| `_lib/applications/homer/base/{service,httproute,namespace}.yaml` | ClusterIP :8080, route, ns |
| `_lib/security/cilium-network-policies/homer-{default-deny,allow}.yaml` | network policy (no CNPG allow — no DB) |

## Security posture

A useful reference for getting a pod through `restricted` PSA cleanly:

- The namespace enforces `pod-security.kubernetes.io/enforce: restricted` (and
  `warn`); the pod spec satisfies it.
- Pod + container: `runAsNonRoot`, `runAsUser`/`Group: 1000`, `fsGroup: 1000`,
  drop ALL caps, seccomp `RuntimeDefault`, `allowPrivilegeEscalation: false`.
- **Set `runAsUser` explicitly.** If you run Kyverno with an
  `add-default-securitycontext` policy, an *unset* `runAsUser` gets mutated to
  `65534`, which won't match the image's baked-in UID 1000. (Lab-wide gotcha —
  see [Best practices](../guides/best-practices.md#kyverno-securitycontext-mutation).)
- Resources: small requests/limits (e.g. `5m`/`16Mi` request, `100m`/`32Mi`
  limit) — it's a static file server.

> **Read-only root FS:** to flip `readOnlyRootFilesystem: true`, first enumerate
> the paths the entrypoint seeds (`/www/assets`, `/run`, `/var/cache/nginx`,
> `/var/log/nginx`, `/tmp` for Alpine nginx) and mount each as an `emptyDir` —
> the same technique as [FreshRSS](freshrss.md#the-securitycontext--writable-paths-pattern).

## Operations

- **Update content:** edit `configmap.yaml` → Flux reconciles. Homer reads config
  at request time; no rollout needed for content changes.
- **Image upgrades:** bump `HOMER_VERSION`. Homer's tags aren't OCI digests
  upstream, so Renovate needs a `regex`-manager entry to track them.
- **Backups:** none — fully reconstructable from git.

> **Behind SSO:** Homer has no native auth. On the internal LAN, gateway access
> is fine; if you ever expose it publicly, put it behind an Authentik
> forward-auth outpost ([Authentik](authentik.md)).
