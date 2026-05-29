# home-0ps lab guide

A build-your-own **GitOps Kubernetes home lab**: Talos Linux on Proxmox,
reconciled by Flux CD, with secrets sourced from 1Password through the External
Secrets Operator and traffic served by a Cilium Gateway. This site is a
**how-to** — follow it to stand up a similar lab on similar hardware.

> Every hostname, IP, pool, and bucket name in this guide is an **example**
> (`lab.example.com`, `10.10.20.0/24`, `tank`, …). Substitute your own — the
> design transfers, the literals don't.

![System context](diagrams/system-context-light.svg#only-light)
![System context](diagrams/system-context-dark.svg#only-dark)

## Start here

<div class="grid cards" markdown>

-   :material-clipboard-check-outline:{ .lg .middle } **Prerequisites**

    ---

    Hardware, network, accounts, and tools you need before the first command.

    [:octicons-arrow-right-24: Prerequisites](prerequisites.md)

-   :material-rocket-launch-outline:{ .lg .middle } **Bootstrap the cluster**

    ---

    The ordered build: provision Talos, bootstrap Flux, then layer the platform.

    [:octicons-arrow-right-24: Bootstrap](bootstrap.md)

</div>

## Reference

<div class="grid cards" markdown>

-   :material-lan:{ .lg .middle } **Infrastructure**

    ---

    The platform layers — networking, DNS, storage, secrets/PKI, observability.

    [:octicons-arrow-right-24: Networking](infra/networking.md) ·
    [DNS](infra/dns.md) ·
    [Storage](infra/storage.md) ·
    [Secrets & PKI](infra/secrets-pki.md) ·
    [Observability](infra/observability.md)

-   :material-apps:{ .lg .middle } **Applications**

    ---

    The workloads — how each is deployed, exposed, and recovered.

    [:octicons-arrow-right-24: Authentik](apps/authentik.md) ·
    [FreshRSS](apps/freshrss.md) ·
    [Homer](apps/homer.md)

-   :material-wrench-outline:{ .lg .middle } **Operations**

    ---

    Day-2: cluster access, hard-won best practices, database rescue.

    [:octicons-arrow-right-24: Cluster access](kubectl-wrapper.md) ·
    [Best practices](guides/best-practices.md) ·
    [Database rescue](guides/cnpg-rescue.md)

</div>

## How the pieces fit

Flux watches the git repo and reconciles the cluster in **dependency-ordered
layers** — each builds on the one before it:

`cluster-config` → `crds` → `controllers` → `pki` → `external-secrets` →
`secrets` → `networking` → `dns` → `storage` → `observability` → `security` →
`apps`

That order *is* the bootstrap order, and it's the spine of the
[Bootstrap](bootstrap.md) guide. Secrets flow **1Password → 1Password Connect →
External Secrets Operator → Kubernetes Secret → workload**; traffic flows
**user → Cilium Gateway → app**, with internal names resolved by a CoreDNS
split-horizon forward.
