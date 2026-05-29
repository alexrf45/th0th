# DNS

The lab runs **two DNS surfaces**: ExternalDNS publishes records for your
services, and a CoreDNS split-horizon forward lets in-cluster workloads resolve
those same internal hostnames.

> **Example values.** `lab.example.com`, `10.10.20.1` (your LAN gateway/DNS
> resolver), and `<app>.int.lab.example.com` are placeholders — substitute your
> own zone and resolver.

**Layer:** `dns` (Flux Kustomization, depends on `secrets`).

## ExternalDNS — publishing records

`_lib/dns/external-dns/` runs ExternalDNS (chart `1.19.0`) with the **UniFi
webhook provider** pointed at the LAN gateway's DNS (`10.10.20.1`). It watches
`HTTPRoute`s and `Service`s and publishes `*.lab.example.com` records into the
gateway's DNS, so LAN clients resolve `<app>.int.lab.example.com` automatically.

If your gateway isn't UniFi, swap the provider — ExternalDNS supports many DNS
backends; only the webhook/provider block changes. Cloudflare credentials are
**not** used here; those are independent and only feed cert-manager DNS-01
(below) — keep edge/DNS-challenge perms separate from record publishing.

## CoreDNS split-horizon — in-cluster resolution

**Problem it solves:** in-cluster back-channels (e.g. Grafana calling Authentik
for an OIDC token exchange) need to resolve `auth.int.lab.example.com`, but
cluster CoreDNS doesn't know your internal zone — it returns NXDOMAIN.

**Fix:** a split-horizon forward so the internal zone resolves via your LAN
resolver:

```
lab.example.com:53 { forward . 10.10.20.1 }
```

Apply it as a Flux-owned patch to the `kube-system/coredns` ConfigMap so it
survives cluster rebuilds (a manual `kubectl edit` is reverted on the next
reconcile or rebuild).

## cert-manager DNS-01 (Let's Encrypt via Cloudflare)

The Let's Encrypt ClusterIssuers solve DNS-01 challenges with a **Cloudflare API
token** scoped `Zone:DNS:Edit` + `Zone:Zone:Read`, stored SOPS-encrypted in
`_lib/networking/clusterissuers/`. Keep this token distinct from any
object-storage token — edge/DNS permissions and storage permissions should never
share a credential. See [Networking](networking.md#tls-and-clusterissuers).

## Gotchas

- **A `*.lab.example.com` wildcard does not cover three-label hosts.**
  `auth.int.lab.example.com` is three labels deep beyond the apex — both DNS and
  the wildcard TLS cert must handle it explicitly (the cert via an explicit SAN).
- **NXDOMAIN on an `<app>.int.*` host:** check ExternalDNS logs *and* that the
  CoreDNS split-horizon forward is present in the live ConfigMap.
