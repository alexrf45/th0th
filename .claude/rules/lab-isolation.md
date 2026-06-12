## Security Lab Isolation — Safety Invariants

The security research range (`terraform/security-lab/`, ADR-0009) detonates
malware, payloads, and vulnerable hosts. These invariants are **non-negotiable**;
violating any one can let a compromised victim pivot to the home/management
network or leak ops credentials. Check them on every change to range networking,
the `scenario-vm` module, or a scenario root.

1. **Detonation VLANs have no gateway.** No UCG SVI, no `proxmox_sdn_subnet`, no
   anycast gateway for any detonation vnet. The air-gap is *structural* — a
   victim has no L3 next-hop off its segment. Never add a gateway "to make
   something reachable"; dual-home an ops box instead.

2. **Only hardened ops boxes are dual-homed into a detonation net.** The Kali
   attacker and the Wazuh collector may carry a second NIC on a detonation vnet.
   Nothing on the management LAN (`192.168.20.0/24`) or TrueNAS ever is.

3. **No scenario/vulnerability disk on TrueNAS.** Every scenario VM disk and every
   Packer golden template lives on **node-local** storage (`local-lvm`/`local-zfs`).
   TrueNAS iSCSI is lab-admin data only (Wazuh index, kept artifacts). The
   `scenario-vm` module's `node_local_datastore` must never be a TrueNAS-backed
   storage id.

4. **Telemetry is detonation → collector, one-way.** Scenario hosts ship logs to
   the Wazuh collector's **detonation-side IP**. No ops secrets — 1Password
   tokens, kubeconfig, SOPS age key, C2 keys — ever transit into a detonation net.

5. **Every detonation VM attaches the `det_isolation` security group** (egress DROP
   to mgmt LAN + ops net) — belt-and-suspenders for an accidental gateway. The
   `scenario-vm` module wires this automatically; do not ship a detonation VM
   without it.

6. **State split:** shared range plumbing → S3 (`range-network/`); each disposable
   scenario → **local** state. A wiped/compromised scenario must never be able to
   corrupt shared infrastructure state.

7. **No EVPN / overlay for the range.** VLAN zones only (ADR-0009). EVPN/OpenFabric
   never worked on this hardware and is abandoned.

**Enabling the cluster-wide Proxmox firewall** (`lab_firewall.enable_cluster_firewall`)
touches every live PVE node and can cut corosync. It is OFF by default; flip it
only via the runbook, policies pinned to ACCEPT, tested on one node first.
