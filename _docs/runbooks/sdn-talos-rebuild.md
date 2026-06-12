# Runbook — rebuild the Talos cluster on the Proxmox EVPN SDN

**Scope:** full teardown → re-provision of the HA Talos cluster on the
`10.30.0.0/24` EVPN overlay (ADR-0008, Option B). Use this when standing the
cluster up from scratch, recovering a broken SDN, or **after a hardware refresh**
(new/added PVE nodes, new gateway). Real lab values throughout — this is an
internal runbook, not the public guide.

> **Companion docs:** [ADR-0008](../decisions/0008-talos-pve-sdn-network-topology.md)
> (why EVPN + flat-L2 BGP peers), and the `project_evpn_openfabric_cant_mesh_shared_lan`
> memory. Read the ADR's "Implementation update (2026-06-10)" section first if the
> SDN control plane is misbehaving.

## Topology at a glance

| Thing | Value |
|---|---|
| PVE hosts | pve01–pve06, mgmt `192.168.20.6`–`.11` on `vmbr0` |
| Mgmt LAN | `192.168.20.0/24` (UniFi UCG-Ultra @ `192.168.20.1`) |
| Overlay subnet | `10.30.0.0/24`, anycast gateway `10.30.0.1`, SNAT on |
| SDN control plane | **flat-L2 BGP-EVPN mesh** — `peers = [all six mgmt IPs]`, VTEP = mgmt IP, **no IGP/loopback fabric** |
| Exit nodes | `pve01` (primary), `pve02` (standby) — L3 egress + SNAT |
| Talos nodes | `10.30.0.200`–`.205`, endpoint `10.30.0.200`, VIP `10.30.0.199` |
| TrueNAS iSCSI | `192.168.20.106:3260` (reached via exit-node SNAT) |
| DNS/NTP for nodes | `10.3.3.1` (UniFi) — applies **post-bootstrap only** |

> **Why no OpenFabric/loopback underlay:** FRR `fabricd` is point-to-point only
> and can't mesh a shared LAN — it broke 4/5 EVPN sessions. The mgmt LAN already
> gives every node direct reachability (corosync rides it), so BGP peers directly
> over mgmt IPs. Full post-mortem in ADR-0008. **Do not reintroduce a fabric on a
> flat LAN.** If a routed underlay is ever wanted, use OSPF (`proxmox_sdn_fabric_ospf`),
> which does broadcast LANs with DR election — not OpenFabric.

## How Terraform is run here

- `terraform/proxmox-base/` — the SDN + Proxmox RBAC root. **Own S3 state.**
- `terraform/dev/` — the Talos cluster (consumes `modules/talos-pve`). **Own S3 state.**
- Both are run **by you, manually, wrapped in the 1Password CLI** (`op run -- terraform …`).
  Claude does not run `plan`/`apply`. `terraform fmt` fails under the op wrapper
  (`interactive IO not available`) — format by hand if needed.
- `terraform.tfvars` in both roots is **SOPS-encrypted**. Decrypt → edit → **re-encrypt
  before committing**. `proxmox-base/terraform.tfvars` carries `pve.password` + the
  1P service-account token — never commit it plaintext.

---

## Phase 0 — Prerequisites

1. **TrueNAS iSCSI authorizes the exit node.** Because the overlay SNATs, every
   initiator appears as the exit node's mgmt IP `192.168.20.6` (not `10.30.0.x`).
   The TrueNAS initiator group must allow **by IQN** or by the `192.168.20.0/24`
   network — **not** by specific node IPs.
   - **Known trap:** the `truenas-primary` initiator group once had IP addresses
     stuffed into the *initiators* (IQN) field as one comma-joined string →
     `iscsiadm: No portals found` / `Could not locate by-path device for LUN N`.
     Fix: clear it to allow-all + use Portal *Authorized Networks*, or list real
     initiator IQNs. Verify before the storage layer reconciles.
2. **Old per-node iSCSI records cleared.** On each PVE host, remove stale
   `storage.cfg` node records referencing prior `dev`/`prod` clusters, or zvol
   creation collides.
3. **1Password reachable** — `op` signed in; the service-account token in
   `proxmox-base/terraform.tfvars` is valid (Phase-2 automation token
   `terraform@pve!tf=…`).
4. **State backends reachable** — S3 remote state for both roots.

---

## Phase 1 — (only if migrating/recovering) tear down the existing SDN

Skip if this is a greenfield SDN. A zone **type** change (e.g. Simple→EVPN) or a
controller `fabric`→`peers` change is **not in-place** — Proxmox won't delete a
zone a vnet still uses, won't create a duplicate-id zone, and a partial apply
leaves pending objects that HTTP-500 the next apply.

**Tear down in dependency order, in the Proxmox UI** (Datacenter → SDN):

1. Delete the **subnet** (under the vnet).
2. Delete the **vnet** (`vtalos`).
3. Delete the **zone** (`talos`).
4. Delete the **controller** (`evpn`).
5. Delete the **fabric** if one exists (legacy OpenFabric). *You cannot delete a
   fabric while a zone references it — that's why the zone goes first.*
6. **SDN → Apply** to commit the teardown.

Then drop the stale addresses from Terraform state so the next apply creates clean:

```sh
op run -- terraform -chdir=terraform/proxmox-base state rm \
  'proxmox_sdn_subnet.this' \
  'proxmox_sdn_vnet.this' \
  'proxmox_sdn_zone_evpn.this' \
  'proxmox_sdn_controller_evpn.this'
# plus any 'proxmox_sdn_fabric_*' addresses if the state predates the 2026-06-10 rewrite
```

> If `terraform plan` already shows the SDN resources as **all-create / 0-destroy**,
> state is already empty (a prior partial run) — skip `state rm`, just apply. The
> leading `proxmox_sdn_applier.finalizer` in `sdn.tf` flushes any leftover pending
> state on the way in.

---

## Phase 2 — apply `proxmox-base` (creates the SDN)

```sh
op run -- terraform -chdir=terraform/proxmox-base plan    # expect: SDN create, peers populated, no fabric
op run -- terraform -chdir=terraform/proxmox-base apply
```

`sdn.tf` stages the objects behind the leading finalizer, then the terminal
`proxmox_sdn_applier.this` commits them in one shot. Confirm in the UI: zone
`talos` green, vnet `vtalos`, subnet `10.30.0.0/24`, controller `evpn` with the
six peers.

> Benign noise: `proxmox_virtual_environment_user` emits an "acl is deprecated"
> warning for every user even with no acl block — provider-level, not fixable in
> HCL. Ignore it.

---

## Phase 3 — verify the BGP-EVPN control plane (the make-or-break step)

**Do not proceed to the dev apply until all six peers are `Established`.** Run on
any PVE host:

```sh
vtysh -c 'show bgp l2vpn evpn summary'
```

✅ **Healthy:** six neighbors, all `Established`, a sane router-id (e.g.
`192.168.20.6`). Per-node `/32`s distributed; non-exit nodes learn a default:

```sh
# on a NON-exit node (e.g. pve03) — should show a BGP default via an exit node:
ip route show vrf vrf_talos        # default nhid … via 192.168.20.6 dev vrfbr_talos proto bgp
```

### Egress test — and the trap that will lie to you

**`ip vrf exec vrf_talos ping …` from a non-exit node ALWAYS shows 100% loss —
this is NOT a fault.** `ip vrf exec` sources from `10.30.0.1`, the **anycast
gateway present on every node**, so replies return to the *exit node's* local copy
of that IP, never back to the originating node. It's a measurement artifact of
testing from an anycast source.

- ✅ **Valid quick test** (from an **exit** node only): `ip vrf exec vrf_talos ping -c2 1.1.1.1` → succeeds.
- ✅ **Definitive test** (any host): boot a throwaway VM with a **unique** overlay IP and ping out:
  ```sh
  # on pve03:
  qm set 9999 --ipconfig0 ip=10.30.0.50/24,gw=10.30.0.1 --nameserver 10.3.3.1
  qm start 9999 && qm terminal 9999     # inside: ping -c2 1.1.1.1 ; ping -c2 10.3.3.1
  ```
  A unique-IP source pinging out = SDN proven end-to-end. **Don't chase the
  `ip vrf exec` 100%-loss result — it's expected.**

> Also expected, not a fault: `show bgp vrf vrf_talos ipv4 unicast 0.0.0.0/0` →
> `% Network not in table` on an exit node. The exit node advertises a default via
> BGP `default-originate` (which doesn't hold the route locally) and egresses via
> its main routing table — the EVPN-originated default shows up as a **type-5** under
> `show bgp l2vpn evpn`, and the proof it propagated is that non-exit nodes learned it.

### If peers are stuck `Connect`/`never` after a recreate

- `systemctl reload frr` on the exit nodes, then **SDN → Apply** again — SNAT/default
  programming sometimes isn't reprogrammed on the first commit after a recreate.
- Confirm it is **not** an OpenFabric fabric (legacy). `show openfabric interface
  detail` showing `Type: p2p, Active neighbors: 1` = the broken model; the fabric
  must be gone and the controller on `peers`.

---

## Phase 4 — UniFi static route (off-Terraform, inbound LAN → overlay)

Without this, LAN clients (and the Talos provider reaching `:50000`) cannot reach
`10.30.0.0/24` — the overlay only SNATs **outbound**.

**UniFi → Settings → Routing → Static Routes → Create:**

| Field | Value |
|---|---|
| Name | `talos-overlay` |
| Type | Static Route / **Next Hop** |
| Destination | `10.30.0.0/24` |
| Next Hop | `192.168.20.6` (pve01 mgmt = primary exit node) |
| Distance | `1` |
| Enabled | ✅ |

- **Next hop is pve01's `192.168.20.6`, not `10.30.0.1`** (the anycast gw lives
  inside the overlay; UniFi can't reach it).
- **Single next hop = no inbound HA.** If pve01 dies, repoint this route to
  `192.168.20.7` (pve02) by hand — UniFi static routes have no next-hop health check.

Verify from a LAN workstation:

```sh
ping -c2 10.30.0.1            # anycast gw, answered by any node (good pre-bootstrap target)
traceroute -n 10.30.0.200    # first hop should be 192.168.20.6
```

---

## Phase 5 — apply the dev cluster + bootstrap

Ensure the SOPS-decrypted `terraform/dev/terraform.tfvars` carries the re-IP
(ADR-0008 items #1–#3): `pve.bridge = "vtalos"`, `pve.gateway = "10.30.0.1"`, node
IPs / `talos.vip_ip` / endpoint / `load_balancer_ip*` on `10.30.0.x`,
`cilium_config.node_network = "10.30.0.0/24"`. `pve.endpoint` stays on the mgmt
LAN (`192.168.20.6`). `ntp_servers`/`nameservers.primary = "10.3.3.1"`.

```sh
op run -- terraform -chdir=terraform/dev plan
op run -- terraform -chdir=terraform/dev apply
```

The provider must now reach `10.30.0.200:50000` (Phase 4 makes this possible). If
it `i/o timeout`s on `talos_machine_configuration_apply`, the SDN/route isn't
healthy — go back to Phase 3/4, **don't** retry-spam the apply.

> **Maintenance-mode NTP/DNS is expected to look wrong.** A node sitting at
> `STAGE: Maintenance` shows `lookup time.cloudflare.com i/o timeout` — that's
> Talos's compiled-in default NTP. Your `10.3.3.1` NTP/DNS only take effect **after
> the machine config applies and the node leaves Maintenance.** Don't debug the
> cloudflare lookup; it disappears at bootstrap.

After apply: `terraform` exports the kubeconfig to 1Password (`memphis-kubeconfig`).

---

## Phase 6 — post-bootstrap verification

```sh
kube dev get nodes                       # all Ready
talosctl -n 10.30.0.200 health           # (talosctl is the one un-wrapped tool — own --talosconfig)
kube dev get ciliuml2announcementpolicy -A
```

- A VM **live-migrated** to another host keeps its IP + L2 (proves the stretched overlay).
- The Talos **VIP fails over** across hosts; the Cilium **LB IP** answers regardless
  of which host the announcer landed on. (Default `externalTrafficPolicy: Cluster`
  for low-replica LBs — `Local` breaks them on L2.)
- Then let Flux reconcile the layers (`cluster-config → crds → … → apps`).

---

## Quick failure index

| Symptom | Cause | Fix |
|---|---|---|
| `iscsiadm: No portals found`, `Could not locate by-path device for LUN N` | initiator group has IPs in the IQN field / stale node records | clear initiator group → allow-all + Portal Authorized Networks; clear old `storage.cfg` records (Phase 0) |
| 4/5 EVPN sessions `Connect`/`never`; `Type: p2p, Active neighbors: 1` | legacy OpenFabric fabric on a shared LAN | remove the fabric; controller on `peers` (Phase 1 + ADR-0008) |
| `ip vrf exec … ping` 100% loss from a non-exit node | anycast-source trap (`10.30.0.1` on every node) | **not a fault** — test from a unique-IP VM (Phase 3) |
| `% Network not in table` for `0.0.0.0/0` on exit node | `default-originate` doesn't hold the route locally | **not a fault** — check non-exit node learned the default |
| egress works only on the exit node after a recreate | SNAT/default not reprogrammed | `systemctl reload frr` on exit nodes + SDN Apply |
| `terraform … dial 10.30.0.20x:50000 i/o timeout` | missing UniFi static route, or unhealthy SDN | Phase 4 route; verify Phase 3 first |
| Talos console stuck on `time.cloudflare.com i/o timeout` | node in Maintenance, pre-bootstrap | expected — clears after config applies (Phase 5) |
| `terraform fmt` → `interactive IO not available` | the op-wrapper pty | format by hand; not a real error |

## Hardware-refresh notes (read before you upgrade)

- **Adding/replacing PVE nodes:** add the new mgmt IP to `sdn.evpn.peers` (and
  `pve.hosts`) — that's the whole SDN control-plane change. Per the DRY-vs-scaling
  rule, scaling must not perturb the existing nodes' render; the flat-peers model
  keeps node addition to a single list entry. Re-apply `proxmox-base`, re-verify
  Phase 3.
- **New gateway with real BGP** (UDM-Pro/SE/Pro-Max/UDW or UXG-Enterprise):
  ADR-0008 Option C (Cilium BGP to the gateway, drop in-overlay L2 announcements)
  becomes low-cost and persistent — revisit it. On a UCG-class gateway it stays
  rejected (root-SSH FRR is non-persistent across firmware updates).
- **Dedicated underlay NIC/VLAN + jumbo frames:** prod-hardening — give VXLAN its
  own NIC/VLAN off `vmbr0` and jumbo the underlay (≥1550) to raise overlay `mtu`
  to 1500. Deferred for the lab.
</content>
</invoke>
