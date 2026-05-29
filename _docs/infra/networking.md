# Networking

The network stack: **Cilium** (CNI + L2 + Gateway API) for pod networking and
north-south ingress, **cert-manager** for TLS, and the **Tailscale operator**
for private operator-only access.

> **Example values.** `lab.example.com` and `<app>.int.lab.example.com` are
> placeholders.

**Layer:** `networking` (Flux Kustomization, depends on `secrets`).

## Cilium (CNI / L2 / Gateway)

> **Cilium is not managed by Flux.** It's rendered by Terraform `helm_template`
> at plan time and shipped as a Talos **inlineManifest** — bootstrap-only. To
> change the **live** cluster, edit the Cilium DaemonSet/ConfigMap directly; to
> change **future bootstraps**, edit the Cilium config in your Talos Terraform
> (`cilium_config.tf`). There is no Cilium HelmRelease in `_lib/`.

- **L2 announcement** provides floating LoadBalancer IPs on a flat LAN — the
  bare-metal equivalent of a cloud provider's floating IP.
- **Gotcha — `externalTrafficPolicy: Local` breaks low-replica LBs:** with few
  replicas the L2 leader node and the pod's node can mismatch, giving connection
  refused. Default to `Cluster`.

## Gateway API

| Path | What |
| --- | --- |
| `_lib/networking/gateway/gatewayclass.yaml` | Cilium GatewayClass |
| `_lib/networking/gateway/gateway.yaml` | the Gateway (`${GATEWAY_NAME}`) in the `networking` ns |
| `_lib/networking/gateway/tls.yaml` | `wildcard-tls` Certificate (see SNI note) |

Apps attach with an `HTTPRoute` whose `parentRefs` point at the Gateway;
namespaces opt in by carrying the `${GATEWAY_NAME}: "true"` label (the Gateway's
`allowedRoutes` selector).

**Gotchas:**

- **Multi-cert SNI doesn't work** on the Cilium Gateway — it serves the first
  `certificateRef` for all SNIs. Use **one wildcard SAN cert** and extend its
  `dnsNames` rather than adding a second `certificateRef`. Because a
  `*.lab.example.com` wildcard doesn't cover three-label hosts, each
  `<app>.int.lab.example.com` host is an explicit SAN.
- **Gateway proxy → backend uses the `reserved:ingress` identity.** Network
  policies gating Gateway backends need `fromEntities: [ingress]`;
  `host`/`remote-node` only covers kubelet probes.

## TLS and ClusterIssuers

`_lib/networking/clusterissuers/` defines `letsencrypt-production` and
`letsencrypt-staging`, both solving DNS-01 via Cloudflare (SOPS-encrypted token).
Put your public wildcard on `letsencrypt-production` to avoid browser
trust warnings. Internal service-to-service TLS uses a separate internal CA — see
[Secrets & PKI](secrets-pki.md).

## Tailscale (private access)

`_lib/networking/tailscale/` runs the operator (chart `1.96.5`) plus a
`ProxyClass`/`ProxyGroup`. Use it for operator-only access to things that should
never face the public internet.

> **Gotcha — Service proxies require privileged.** The operator's `sysctler`
> init container is hardcoded privileged, which collides with a restricted PSA /
> Kyverno posture. For non-HTTP workloads, prefer a Cilium Gateway `HTTPRoute`
> over a Tailscale Service proxy. Where the proxy is genuinely needed, carve out
> a narrow Kyverno allowlist entry rather than loosening the cluster default.
