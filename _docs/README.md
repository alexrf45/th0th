# home-0ps.com

A home lab built following GitOps principles using Talos Linux on Proxmox & Flux CD with secrets sourced from 1Password

![System context](diagrams/system-context-light.svg#only-light)
![System context](diagrams/system-context-dark.svg#only-dark)

## Start here

<div class="grid cards" markdown>

-   :material-clipboard-check-outline:{ .lg .middle } __[Prerequisites](prerequisites.md)__

    ---

    Hardware, network, accounts, and tools you need before the first command.

-   :material-rocket-launch-outline:{ .lg .middle } __[Bootstrap the cluster](bootstrap.md)__

    ---

    The ordered build: provision Talos, bootstrap Flux, then layer the platform.

</div>

## Reference

<div class="grid cards" markdown>

-   :material-lan:{ .lg .middle } __[Infrastructure](infra/index.md)__

    ---

    The platform layers — networking, DNS, storage, secrets/PKI, observability.

-   :material-apps:{ .lg .middle } __[Applications](apps/index.md)__

    ---

    The workloads — how each is deployed, exposed, and recovered.

-   :material-wrench-outline:{ .lg .middle } __[Operations](guides/index.md)__

    ---

    Day-2: cluster access, hard-won best practices, database rescue.

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
