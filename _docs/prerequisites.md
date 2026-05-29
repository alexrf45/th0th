# Prerequisites

What you need before the first command. None of the specific products are
load-bearing — anything that fills the same role works — but this is the stack
the rest of the guide assumes.

## Hardware

| Role | This lab uses | Minimum that works |
| --- | --- | --- |
| Compute | several low-power x86 mini-PCs | 1 capable host; 3+ to learn HA |
| Hypervisor | Proxmox VE cluster | any platform that boots Talos (Proxmox, bare metal, a cloud VM) |
| Storage | a ZFS NAS (TrueNAS Scale) | any iSCSI/NFS target; or skip and use local-path only |
| Network | a managed switch + a gateway/router with custom DNS | any LAN where you control DNS records |

A single mini-PC and node-local storage is enough to follow most of the guide;
the multi-node + NAS setup exists to exercise HA and durability patterns.

## Network

- A **LAN subnet** you control — examples use `10.10.20.0/24`.
- A **domain** for internal services — examples use `lab.example.com`. A real
  registered domain helps (Let's Encrypt + a public status page later), but an
  internal-only zone works.
- The ability to **publish DNS records** on your gateway (this lab uses a UniFi
  gateway via ExternalDNS; any ExternalDNS-supported provider is fine).

## Accounts & services

| Service | Used for | Required? |
| --- | --- | --- |
| A secrets manager (this lab: **1Password** + Connect) | source of truth for all secrets via External Secrets | yes (or swap the ESO backend — Vault, cloud secret managers, etc.) |
| **Cloudflare** | DNS-01 certificate challenges; optional public exposure via Tunnel | recommended |
| A **Slack** workspace | Alertmanager notifications | optional |

## Tools on your workstation

- `terraform` (or OpenTofu) — provisions Talos VMs on Proxmox
- `talosctl` — talks to Talos nodes
- `kubectl`, `helm`, `flux`, `kustomize` — cluster + GitOps
- `op` (1Password CLI) — fetches the kubeconfig on demand (see
  [Cluster access](kubectl-wrapper.md))
- `sops` + `age` — encrypts secrets that live in git

## Mental model

The cluster is **declarative and disposable**. Everything except persistent data
is in git; Flux reconciles it. You should be able to destroy and re-provision the
cluster and have it return to the same state — so durability lives in the
**storage layer** (ZFS redundancy + snapshots), not in pet workloads. Keep that
in mind as you go: if a step feels like it's creating something you'd be afraid
to lose, it belongs on the NAS or in your secrets manager, not on a node.

Ready? Continue to [Bootstrap the cluster](bootstrap.md).
