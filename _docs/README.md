# home-0ps.com

A home lab built following GitOps principles using Talos Linux on Proxmox & Flux CD with secrets sourced from 1Password

![System context](diagrams/system-context-light.svg#only-light)
![System context](diagrams/system-context-dark.svg#only-dark)

## Start here

<div class="grid cards" markdown>

- :material-clipboard-check-outline:{ .lg .middle } **[Prerequisites](prerequisites.md)**

  ***

  Hardware, network, accounts, and tools you need before the first command.

- :material-rocket-launch-outline:{ .lg .middle } **[Bootstrap the cluster](bootstrap.md)**

  ***

  The ordered build: provision Talos, bootstrap Flux, then layer the platform.

</div>

## Reference

<div class="grid cards" markdown>

- :material-lan:{ .lg .middle } **[Infrastructure](infra/networking.md)**

  ***

  The platform layers — networking, DNS, storage, secrets/PKI, observability.

  [Networking](infra/networking.md) ·
  [DNS](infra/dns.md) ·
  [Storage](infra/storage.md) ·
  [Secrets & PKI](infra/secrets-pki.md) ·
  [Observability](infra/observability.md)

- :material-apps:{ .lg .middle } **[Applications](apps/authentik.md)**

  ***

  The workloads — how each is deployed, exposed, and recovered.

  [Authentik](apps/authentik.md) ·
  [FreshRSS](apps/freshrss.md) ·
  [Homer](apps/homer.md)

- :material-wrench-outline:{ .lg .middle } **[Operations](kubectl-wrapper.md)**

  ***

  Day-2: cluster access, hard-won best practices, database rescue.

  [Cluster access](kubectl-wrapper.md) ·
  [Best practices](guides/best-practices.md) ·
  [Database rescue](guides/cnpg-rescue.md)

</div>

## How the pieces fit

Flux watches the git repo and reconciles the cluster in **dependency-ordered
layers** — each builds on the one before it:

`cluster-config` → `crds` → `controllers` → `pki` → `external-secrets` →
`secrets` → `networking` → `dns` → `storage` → `observability` → `security` →
`apps`

That order _is_ the bootstrap order, and it's the spine of the
[Bootstrap](bootstrap.md) guide. Secrets flow **1Password → 1Password Connect →
External Secrets Operator → Kubernetes Secret → workload**; traffic flows
**user → Cilium Gateway → app**, with internal names resolved by a CoreDNS
split-horizon forward.
