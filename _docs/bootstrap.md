# Bootstrap the cluster

The build runs in **dependency-ordered layers** — Flux reconciles them top to
bottom, and that order is also the order you bring the lab up. Each step links to
the reference page with the detail.

```
cluster-config → crds → controllers → pki → external-secrets →
secrets → networking → dns → storage → observability → security → apps
```

Every layer `dependsOn` the one above it, so a fresh cluster converges in one
direction and a single broken layer can't wedge unrelated ones.

## 1. Provision Talos on Proxmox (Terraform)

Stand up the VMs and install Talos Linux. The Talos machine config also ships
**Cilium** as an inline manifest (rendered by Terraform at plan time), so the CNI
is present the moment the cluster boots — there's no Cilium HelmRelease to
reconcile later.

- Provision with the Talos Terraform module; the operator runs `terraform plan`
  / `apply` (credentials via the 1Password CLI).
- The module exports each cluster's kubeconfig into your secrets manager as a
  Secure Note — never to disk. See [Cluster access](kubectl-wrapper.md).

> Why Talos: an immutable, API-driven OS with no SSH and a locked-down kube API.
> It makes the cluster reproducible and shrinks the attack surface — see
> [Best practices §8](guides/best-practices.md#things-to-skip-on-a-talos-lab).

## 2. Bootstrap Flux

Point Flux at the git repo's branch; from here, **git is the control plane**.
Flux reads `_clusters/<env>/cluster.yaml`, which defines the layered
Kustomizations below. The Age key for SOPS decryption is seeded from your secrets
manager at this step.

## 3. Platform layers (Flux reconciles in order)

| Layer | What it stands up | Reference |
| --- | --- | --- |
| `cluster-config` | the ConfigMap of `${VAR}`s (hostnames, versions, storage params) substituted into every downstream manifest | — |
| `crds` | global CRDs (Prometheus Operator, CNPG, …), version-pinned, installed *before* the operators that use them | [Best practices §1](guides/best-practices.md#1-gitops-discipline) |
| `controllers` | the operators: cert-manager, CloudNativePG, External Secrets, Kyverno, Renovate, … | — |
| `pki` | the internal CA + trust-manager (service-to-service TLS) | [Secrets & PKI](infra/secrets-pki.md#internal-pki) |
| `external-secrets` | the ESO deployment (depends on controllers + pki for mTLS) | [Secrets & PKI](infra/secrets-pki.md) |
| `secrets` | 1Password Connect + the ClusterSecretStore apps reference | [Secrets & PKI](infra/secrets-pki.md#secret-flow) |
| `networking` | Cilium Gateway, cert-manager ClusterIssuers, Tailscale operator | [Networking](infra/networking.md) |
| `dns` | ExternalDNS (record publishing) + the CoreDNS split-horizon forward | [DNS](infra/dns.md) |
| `storage` | the iSCSI CSI driver, local-path, VolumeSnapshot infra | [Storage](infra/storage.md) |
| `observability` | kube-prometheus-stack + Alloy → off-cluster Loki | [Observability](infra/observability.md) |
| `security` | per-app Cilium NetworkPolicies, Kyverno policies, Falco rules | [Best practices §2](guides/best-practices.md#2-security--hardening) |

After this, you have a running platform with no application workloads yet.

## 4. Set your secrets first

Several apps expect secrets to exist *before* their first boot (e.g. an OIDC
client pair shared by the IdP and its consumer). Create the 1Password items up
front — see the [Authentik OIDC item format](apps/authentik.md#oidc-client-item-format)
for the canonical example — so ESO can sync them the moment the app installs.

## 5. Ship your first app

Start with something stateless to prove the gateway, DNS, TLS, and PSA path
end-to-end before adding a database:

1. **[Homer](apps/homer.md)** — a static dashboard, no DB, no secrets. The
   simplest possible `restricted`-PSA-compliant workload.
2. **[FreshRSS](apps/freshrss.md)** — adds a CNPG database on a static iSCSI
   volume and the non-root-entrypoint hardening pattern.
3. **[Authentik](apps/authentik.md)** — single sign-on, and wiring OIDC consumers
   as config-as-code.

Each app is its **own top-level Flux Kustomization** that `dependsOn` the layers
it needs (dns, networking, security, and storage/secrets if it's stateful). Add a
new app by adding its Kustomization to `cluster.yaml` — never by folding it into
a shared bucket.

## Where to go next

- Harden and make resilient: [Best practices](guides/best-practices.md).
- Know your recovery story before you need it:
  [Database rescue](guides/cnpg-rescue.md).
