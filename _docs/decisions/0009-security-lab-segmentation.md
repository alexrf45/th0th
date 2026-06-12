# ADR-0009: Security research lab — network segmentation & range topology

- **Status:** **Accepted** 2026-06-11. The lab is pivoting to a security research range (offensive + defensive practice, bespoke Linux/Windows tooling & detections, CVE testing). Segmentation is enforced with **Proxmox SDN VLAN zones backed by the UniFi switch**; the EVPN overlay is abandoned (deleted from the live cluster 2026-06-10). Implemented in `_infra/terraform/security-lab/range-network/`.
- **Date:** 2026-06-11
- **Deciders:** fr3d (with Claude review)
- **Related:** [ADR-0008](0008-talos-pve-sdn-network-topology.md) (EVPN/Simple-zone L2 behavior — the air-gap primitive reused here), [ADR-0004](0004-gpu-vfio-passthrough.md) (anubis GPU node). Supersedes the EVPN approach **for the range** (the prod-cluster networking question is tracked separately).

## Context

The lab is repurposed from a GitOps services cluster to a **security research range**. The explicit gap is **network segmentation at the hypervisor level**: detonation of malware/payloads and vulnerable hosts must not be able to reach the home/management LAN (`192.168.20.0/24`), TrueNAS, the internet, or each other — even if a victim VM is fully compromised. Environments must be **reproducible** (Terraform + Packer).

The EVPN SDN overlay was deleted by the user on 2026-06-10; it never worked. This is the third overlay attempt to fail on this hardware (OpenFabric → flat-L2 BGP-EVPN). Root cause is structural and unfixable here: the UCG-Ultra has no persistent BGP, and FRR `fabricd` is point-to-point only and cannot mesh a shared LAN (ADR-0008). The range therefore avoids overlays entirely.

### Hardware constraints (unchanged from ADR-0008)
- Gateway: UCG-Ultra @ UniFi OS — **no persistent BGP**, but full **802.1Q VLAN** support.
- Switch: UniFi 16-port — VLAN trunking is robust and persistent across firmware.
- Compute: 6× Beelink S13 (pve01–pve06) on `vmbr0`, mgmt `192.168.20.6–.11`. TrueNAS `192.168.20.106`. anubis `192.168.20.87`.

## Decision

**Segmentation = Proxmox SDN VLAN zone on `vmbr0`, one vnet per VLAN, carried over the UniFi switch trunk.** True cross-node L2 (a DC on pve01 and a workstation on pve04 share a broadcast domain — needed for AD broadcast/poisoning attacks), enforced at both the switch **and** the hypervisor.

### Air-gap is structural, not rule-based
A VLAN zone provides **no gateway**. A detonation VLAN is given **no UCG SVI** and **no Proxmox SDN subnet**, so it is a gateway-less L2 island — a compromised victim has no L3 next-hop off its segment. The only bridges in are deliberately **dual-homed ops boxes** (Kali attacker, Wazuh collector) that also carry a NIC on the detonation vnet. Telemetry flows det → collector one-way, to the collector's detonation-side IP only.

| VLAN | vnet | Subnet | Gateway | Egress | Purpose |
|------|------|--------|---------|--------|---------|
| 40 | `vlabops` | 10.40.0.0/24 | UCG SVI (firewalled) | WAN allow-list | Kali, Wazuh, C2, orchestration |
| 50 | `vdet00` | 10.50.0.0/24 | **none** | **none (air-gap)** | AD detection lab victims |
| 5N | `vdetNN` | 10.5N.0.0/24 | none | none | future scenarios |

### Defense-in-depth (three layers)
1. **Physical (UniFi):** lab VLANs trunked to PVE ports; detonation VLANs have no SVI; ops VLAN gateway is firewalled (WAN allow-list, no route to mgmt LAN).
2. **Hypervisor (Proxmox SDN VLAN zone):** `proxmox_sdn_zone_vlan` + per-VLAN `proxmox_sdn_vnet`.
3. **Per-VM firewall:** the `det_isolation` cluster security group (egress DROP to mgmt LAN + ops net) attached to every detonation VM by the `scenario-vm` module — catches an accidental SVI/gateway on a detonation VLAN.

### Storage split
- **TrueNAS iSCSI = lab-admin data only** (Wazuh long-term index, kept artifacts). Reachable from ops; unreachable from detonation.
- **Node-local (`local-lvm`/`local-zfs`)** for **all scenario VM disks and Packer templates** — vulnerability data never lands on the NAS; blast radius stays on the node.

### State split (per `.claude/rules/terraform-buisness-rules.md`)
- Shared range plumbing (VLAN zones, datacenter firewall) → **S3** (`_infra/terraform/security-lab/range-network/`). Kept in its own root, **not** `_infra/terraform/modules/proxmox-base/`, to avoid entangling with the deleted-EVPN drift in that state and its SOPS-secret tfvars.
- Each disposable scenario → **local** state (`_infra/terraform/security-lab/scenarios/<name>/`).

## Alternatives considered

- **Simple zone, one node per scenario** — no switch config, but per-node isolated L2 means no cross-node L2 and a scenario is capped to one Beelink's RAM. Rejected: AD scenarios want cross-node L2 and headroom.
- **VXLAN/EVPN overlay** — stretched L2 across nodes, but overlays have failed three times on this hardware; the UCG can't anchor them durably. Rejected on durability.
- **Lab SDN inside `_infra/terraform/modules/proxmox-base`** (as first sketched) — rejected: that state still defines the dead EVPN zone (drift) and its tfvars is a SOPS secret we must not edit; a separate root is cleaner and independently deployable.

## Consequences

- **Positive:** robust, persistent segmentation on hardware-supported primitives; structural air-gap that survives a full victim compromise; reproducible; decoupled from the (down) prod k8s cluster; clean S3-vs-local state split.
- **Negative / follow-ups:**
  - Detonation cross-node L2 depends on correct UniFi trunk + no-SVI config — a click-ops step (documented in the runbook; optionally codified later with `paultyng/unifi`).
  - `_infra/terraform/modules/proxmox-base` still contains the dead EVPN `sdn.tf` (state drift). Excising it touches the prod-cluster networking contract and its SOPS tfvars — tracked as a separate decision, **out of scope here**. Do not `apply` proxmox-base until that is resolved.
  - `vmbr0` must be VLAN-aware on every node (prerequisite).
  - Enabling the cluster-wide firewall is a guarded manual step (corosync risk); default OFF.
