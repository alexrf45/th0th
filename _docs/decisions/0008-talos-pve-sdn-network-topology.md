# ADR-0008: talos-pve cluster network topology on the Proxmox SDN

- **Status:** **Accepted (Option B, EVPN-on-fabric)** 2026-06-08 — gateway confirmed UCG-Ultra @ UniFi OS 5.1.15 (no persistent BGP) → C rejected on durability; B chosen. Hosts on PVE 9.2.3 → EVPN with an OpenFabric routed underlay; written into `terraform/proxmox-base/sdn.tf` (not yet applied). Cilium-BGP-over-Proxmox-FRR kept as a later enhancement. (Earlier draft weighed C-primary assuming clean gateway BGP — superseded by the hardware fact.) See the Implementation note below.
- **Date:** 2026-06-08
- **Deciders:** fr3d (with Claude review)
- **Related:** [ADR-0006](0006-talos-pve-module-refactor.md) (the module refactor that parameterized `pve.bridge`/`pve.gateway`); `project_talos_pve_sdn_migration`, `project_proxmox_base_tf_root`, `project_cilium_l2_traffic_policy` (memory). Tracked as the **TP-tier** in `_docs/reviews/home-0ps-review-2026-06-08.md`.

## Context

`terraform/proxmox-base/` now provisions a Proxmox **SDN Simple zone** `talos` → vnet
`vtalos` → subnet `10.30.0.0/24` (gateway `10.30.0.1`, SNAT), applied and verified
2026-06-08. The next workstream is to move the Talos cluster
(`terraform/modules/talos-pve`, consumed by `terraform/dev/`) **off the flat LAN
`192.168.20.0/24`** and onto that vnet.

The blocker is not the re-IP — the module is already parameterized for it
(`var.pve.bridge`, `var.pve.gateway`, `var.cilium_config.node_network`). The blocker is
a **network-topology mismatch**: the cluster's HA design assumes a single stretched L2
broadcast domain, and a Simple zone deliberately does not provide one.

### The two L2 dependencies in the module

1. **Talos control-plane API VIP** — `talos.tf:44-47` sets `eth0.vip.ip = var.talos.vip_ip`.
   This is Talos's own shared-IP feature: one control-plane node holds the VIP and
   advertises it by **gratuitous ARP**; on failover another node ARPs to claim it. The
   k8s API HA front-end (`cluster_endpoint = https://${var.talos.endpoint}:6443`) rides on
   this. **Requires all control-plane nodes on one L2 segment.**
2. **Cilium L2 LoadBalancer announcements** — `cilium_config.tf:43` (`l2announcements.enabled`)
   + the `CiliumL2AnnouncementPolicy`/`CiliumLoadBalancerIPPool` in `locals.tf:61-100`.
   Worker nodes answer **ARP** for LoadBalancer IPs carved from `node_network`
   (`load_balancer_start..stop`). The Cilium Gateway / ingress LB IP is announced this way.
   **Requires the LB IPs and the nodes announcing them on one L2 segment.**

### Why the Simple zone breaks both

A **Simple zone is per-node isolated L2 with L3 routing between hosts** — each PVE host
gets its own local bridge for `vtalos`; cross-host traffic is *routed*, not bridged. So
two VMs on the vnet but on different hosts are in different broadcast domains. GARP (VIP)
and ARP (Cilium L2) do not cross hosts. This is the `project_cilium_l2_traffic_policy`
failure mode, but total: the VIP can't fail over across hosts, and LB IPs only answer on
whichever host the announcing node landed on. A single-host deployment works; multi-host
HA does not.

### Re-IP changes required regardless of option

These are mechanical and identical for all three options (do them once, in `terraform/dev`'s
encrypted tfvars + the SDN root):

| # | Change | Where |
|---|--------|-------|
| 1 | `pve.bridge = "vtalos"` | dev tfvars (`var.pve.bridge`) |
| 2 | `pve.gateway = "10.30.0.1"` | dev tfvars (`var.pve.gateway`; feeds `ip_config.gateway`, `pve.tf:70,164`) |
| 3 | `cilium_config.node_network = "10.30.0.0/24"`; node IPs, `talos.vip_ip`/endpoint, `load_balancer_ip*` → `10.30.0.x` | dev tfvars (CIDR validations in `variables.tf` re-check automatically) |
| 4 | **Off-TF:** LAN clients can't reach `10.30.0.0/24` (SNAT egress only). Add a UniFi static route `10.30.0.0/24 → <a PVE host>`, **or** reach services only via Cloudflare Tunnel / Tailscale | UniFi; out of Terraform |
| 5 | Update ExternalDNS records + CoreDNS split-horizon (`var.nameservers.internal`, th0th.dev→UniFi) for the new IPs | GitOps `_lib/`, dev tfvars |
| 6 | `config-export.tf` kubeconfig server tracks `talos.endpoint` automatically — no change beyond the re-IP | module (automatic) |

The options differ only in **how the cluster gets a working stretched-L2-or-equivalent
fabric** — items #1–#6 are constant.

## Options

### Option A — Single-host validation (keep the Simple zone, no HA)

Pin every control-plane and worker node to **one** PVE host (`controlplane_nodes[*].node`
/ `worker_nodes[*].node` all set to e.g. `pve01`). All VMs then share that host's local
`vtalos` bridge — one L2 segment — so the Talos VIP and Cilium L2 work **unchanged**. Only
the #1–#6 re-IP is needed; zero topology rework.

- **Pros**
  - Smallest possible change; unblocks an end-to-end apply *today* on the already-deployed Simple zone.
  - Validates the whole new path at once: token (Phase-2), SDN vnet attach, gateway/SNAT egress, storage datastores, image download, bootstrap, kubeconfig export.
  - Reversible — it's a tfvars change, not a topology commitment.
- **Cons**
  - **No HA.** Single physical host = SPOF; etcd "quorum" on one box is theatre. Defeats the lab's HA goal.
  - Concentrates all CPU/RAM/disk on one Beelink — capacity-bound.
  - Not a destination, only a smoke test. You still have to pick B or C afterward.

### Option B — EVPN zone (stretched L2 across hosts via VXLAN + BGP-EVPN)

Replace `proxmox_sdn_zone_simple` in `proxmox-base/sdn.tf` with an **EVPN** zone: add a
`proxmox_sdn_controller` (type `evpn`, an ASN, `peers` = the PVE host IPs), point the zone
at it, set a VRF/VXLAN tag, and designate **exit node(s)** for L3 egress + SNAT. EVPN gives
a VXLAN overlay (stretched L2 across all hosts) **plus** an anycast gateway and routed exit
— which is exactly the `gateway 10.30.0.1` + `snat` shape the subnet already declares. The
**talos-pve module is unchanged**: the VIP and Cilium L2 design port over verbatim, just re-IP'd.

- **Pros**
  - **Lowest module churn** — the existing L2 HA design works as-is; only the SDN root changes.
  - Restores true cross-host stretched L2 → multi-host HA for both the VIP and Cilium L2.
  - Self-contained in Proxmox; no dependency on UniFi BGP capability.
  - Most production-like *Proxmox* pattern; EVPN is the supported way to stretch L2 across an SDN cluster.
- **Cons**
  - Re-creates a flat L2 inside an overlay — the `project_cilium_l2_traffic_policy` fragility (leader/announcer-node mismatch, `externalTrafficPolicy` foot-guns) **still applies**, now one layer deeper and harder to debug.
  - Adds real hypervisor-layer complexity: an EVPN controller, BGP between nodes, exit-node selection (the exit node becomes a routing SPOF unless you run redundant exit nodes), VXLAN MTU bookkeeping (`sdn.mtu`).
  - Tears down + re-applies the SDN zone (the Simple zone is replaced, not extended).
  - VXLAN encap overhead + an extra failure domain to monitor.

### Option C — Drop the L2 dependency (routed endpoint + Cilium BGP) on the Simple zone

Keep the **Simple zone as-is** (it's already applied, and per-node-L3 is the more scalable
model) and remove the cluster's reliance on stretched L2:

1. **Replace the Talos L2 VIP** (`eth0.vip`) with a routed control-plane endpoint — kube-vip
   in **BGP** mode, or an external HAProxy/LB in front of the three API servers, or a UniFi-side
   VIP. `talos.endpoint`/`cluster_endpoint` point at that; the `vip:` block is deleted.
2. **Replace Cilium L2 announcements with the Cilium BGP Control Plane** — `l2announcements`
   off; add `CiliumBGPClusterConfig`/`CiliumBGPPeerConfig` + advertisements so Cilium peers
   BGP with the upstream router (UniFi Cloud Gateway FRR, or a Proxmox-node FRR) and advertises
   LoadBalancer IPs as /32 routes. No ARP anywhere.

- **Pros**
  - **Eliminates the entire L2-fragility class** — `project_cilium_l2_traffic_policy`, GARP races, announcer-node mismatch all disappear. This is the recurring bug category in the lab's memory.
  - Most production / cloud-native — BGP-to-fabric is how real clusters advertise LB IPs; matches the lab's stated "as close to production as possible" goal.
  - **No SDN rework** — builds on the Simple zone already deployed; routing is the zone's native model.
  - Scales cleanly: add hosts/nodes without overlay or L2-domain concerns.
- **Cons**
  - **Largest module change** — rip out `eth0.vip` and the `CiliumL2*` manifests; add BGP cluster/peer/advertisement CRs to the Cilium inline-manifest bootstrap; provide a routed CP endpoint (kube-vip BGP or external LB).
  - **External dependency / open question:** needs a BGP-capable upstream peer. UniFi Cloud Gateway BGP support is model- and firmware-dependent (FRR config upload on newer Network releases) and clunky; the Simple zone's per-node FRR may not cleanly accept Cilium peers either. **If no workable BGP peer exists, C is blocked** → fall back to B.
  - Upstream must accept/route the LB pool prefix; more cross-domain (UniFi + cluster) coordination.
  - Changes the control-plane HA mechanism (kube-vip/LB) — a new component to operate.

## Recommendation — phased: **A now, then B (EVPN) as the HA target** (gateway confirmed: UCG-Ultra @ UniFi OS 5.1.15)

> **Hardware fact that decides this (confirmed 2026-06-08):** the lab gateway is a **UCG-Ultra
> on UniFi OS 5.1.15**. The UCG-Ultra is **not** on Ubiquiti's official BGP list even on current
> UniFi OS 5.x (BGP UI is EFG/UDM-Pro/SE/Pro-Max/UDW + UXG-Enterprise only). So gateway-side BGP
> for Option C would be **unofficial root-SSH FRR that does not persist across firmware updates /
> re-provisioning**. This inverts the earlier C-primary weighting below.

1. **Phase 1 — do Option A immediately.** It's a tfvars-only change on the
   already-deployed Simple zone and de-risks everything that is *not* topology: Phase-2
   token auth against real VM creates, vnet attach, gateway/SNAT egress, storage datastores,
   image pull, bootstrap, and kubeconfig export. A single-host cluster proves the plumbing
   end-to-end and is cheap to throw away. **Do not stop here — A is a smoke test, not a
   destination** (no HA).

2. **Phase 2 — target Option B (EVPN).** C's whole value proposition was *clean, persistent,
   gateway-native BGP*. On a UCG-Ultra that doesn't exist: BGP there is root-SSH FRR that a
   firmware update can silently wipe — a routing control-plane that vanishes on upgrade is
   **worse** fragility than the L2 problem we're escaping, and it violates the lab's production/DR
   goals. The only *persistent, IaC-managed* way to do C is to peer Cilium with a BGP speaker that
   is **not** the UCG — i.e. the Proxmox nodes — but running BGP on Proxmox **is** adopting EVPN.
   So the paths converge: **B (EVPN)** keeps the routing/L2 fabric inside Terraform-managed Proxmox
   (persistent, reproducible, DR-friendly), needs **zero** UniFi BGP, and ports the module's existing
   VIP + Cilium L2 design over unchanged.

3. **Future enhancement (the "best of both", once on B):** after EVPN is up, you can *optionally*
   peer Cilium BGP with the **Proxmox EVPN FRR** — single-hop, on-subnet, persistent, IaC-managed —
   and retire the in-overlay Cilium L2 announce. That captures C's "no L2 fragility" benefit without
   ever touching the fragile UCG. Treat it as an optimization after B is proven, not a Phase-2 blocker.

Rationale: A validates the data path on the existing zone with near-zero change; B is the only
option that delivers cross-host HA on this hardware **without** depending on a non-persistent,
unofficial gateway feature. Option **C-via-UCG is rejected** for this lab on durability grounds;
**C-via-Proxmox-FRR** survives only as the layer-on-top-of-B enhancement in (3).

This **re-aligns with the original `project_talos_pve_sdn_migration` memory note's B-primary ranking**
— but now for a concrete hardware reason (UCG-Ultra has no persistent BGP), not merely least-churn.
The intermediate C-primary weighting in this ADR assumed clean gateway BGP; the confirmed gateway
model removes that assumption. If a UDM-Pro/SE/Pro-Max/UDW or UXG-Enterprise is ever added to the
lab, revisit C (official UI BGP would make it low-cost and persistent again).

## Research note — UniFi BGP feasibility for Option C (2026-06-08)

Live-doc research (Ubiquiti Help Center + community guides for Talos+Cilium+UniFi):

- **Official in-UI BGP** (Settings → Routing → BGP, FRR-format config upload) is supported only
  on **UDM / UDM-Pro / UDM-SE / UDM-Pro-Max / UDW / EFG** (UniFi OS **4.1.13+**) and
  **UXG-Enterprise** (**4.1.8+**). The standard Cloud Gateways (**UCG-Ultra / UCG-Max / UCG-Fiber**)
  are **not** on the official list — **re-confirmed 2026-06-08 against current UniFi OS 5.x: the
  UCG-Ultra (the lab's gateway, on 5.1.15) is still excluded.**
- **Standard Cloud Gateways still run FRR** and the community peers Cilium successfully on them via
  **root SSH** (`/etc/frr/frr.conf` + `bgpd=yes` in `/etc/frr/daemons`). Documented working setups:
  UCG-Ultra + Talos + Cilium, and UCG-Max + Proxmox-Talos + Cilium (≈ this lab's stack).
  **Caveat: unofficial + the FRR config can be wiped on firmware update / re-provisioning** (no UI
  backup-restore) → an ongoing operational tax. This is the deciding factor for the model in hand.
- **Cilium 1.19.4 (pinned) uses BGPv2** — `CiliumBGPClusterConfig` + `CiliumBGPPeerConfig` +
  `CiliumBGPAdvertisement` + `CiliumLoadBalancerIPPool` (the old `CiliumBGPPeeringPolicy` was removed
  in 1.19). eBGP, private ASNs 64512–65534, advertise LoadBalancer IPs as /32s.
- **Two clean fits with this module:** (1) the BGP node label (`bgp-policy: active`) is set via Talos
  `machine.nodeLabels` in the config patch — **not** a post-bootstrap `kubernetes_labels` resource —
  sidestepping the ADR-0006 Sprint-6 apply-ordering foot-gun (#15). (2) the LB pool no longer has to be
  carved from `node_network`; give it its own CIDR (e.g. `10.30.255.0/24`) since BGP routes it.
- **SDN-specific wrinkle (NOT covered by the flat-LAN tutorials):** the blogs put nodes on the same
  subnet as the UniFi gateway. Here the nodes are on an isolated SNAT'd SDN subnet, so a node→UniFi
  BGP session would be SNAT'd by Proxmox and fail to establish. Option C therefore requires one of:
  **(a)** make `10.30.0.0/24` routed not SNAT-isolated (drop SNAT + UniFi static route — folds into
  re-IP item #4) and peer UniFi; **(b)** peer Cilium with the Proxmox-node Simple-zone FRR at
  `10.30.0.1` and redistribute up to UniFi; or **(c)** use EVPN (Option B) and peer at the EVPN gateway.

**Net:** C is feasible on this hardware class. Its cost is model-dependent — *low* on a UDM/UXG-E
(official, persistent, UI-managed) and *moderate* on a UCG (root-SSH FRR, non-persistent across
updates) — plus the SDN routing change (a) above. Confirm the exact gateway model before committing.

## Implementation note — B on PVE 9.2.3, OpenFabric underlay (2026-06-08)

Gateway confirmed UCG-Ultra @ 5.1.15 → **Option B accepted** as the HA target. Hosts run
**Proxmox VE 9.2.3**, which has the SDN **fabric** feature, so B uses the *routed-underlay*
form rather than a flat-L2 BGP `peers` mesh:

- **Underlay:** `proxmox_sdn_fabric_openfabric` (IS-IS) + per-node `proxmox_sdn_fabric_node_openfabric`.
  Each PVE node (pve01–pve06, mgmt `192.168.20.6`–`.11`) gets a loopback router-id from a dedicated
  `ip_prefix` (`10.30.255.0/24`); IS-IS adjacencies form over **`vmbr0`** (the flat management L2).
- **Control plane:** `proxmox_sdn_controller_evpn` with `fabric = <fabric id>` (peers auto-discovered
  via the fabric — no hardcoded peer IPs).
- **Overlay:** `proxmox_sdn_zone_evpn` (`vrf_vxlan = 4000`) → `proxmox_sdn_vnet` (`tag = 10300`,
  must differ from `vrf_vxlan`) → `proxmox_sdn_subnet` (`10.30.0.0/24`, anycast gw `10.30.0.1`, SNAT).
  Egress via `exit_nodes = [pve01, pve02]`, `primary_exit_node = pve01`.
- **Written into the repo 2026-06-08:** `terraform/proxmox-base/sdn.tf` now carries the EVPN-on-fabric
  resources (replacing the Simple zone) and `variables.tf` `var.sdn` gained the `evpn`/`fabric` shape.
  All grounded in bpg/proxmox **v0.107.0** schemas (pinned). **Not yet applied** — the encrypted
  `terraform.tfvars` still needs the `sdn.evpn` block (user-managed SOPS file), and applying replaces
  the live Simple zone. **This commits to EVPN directly and skips the Option-A single-host smoke test**
  (user's call).
- **Prod-hardening flags (deferred):** the fabric shares `vmbr0` with VXLAN data traffic (give it a
  dedicated NIC/VLAN for prod); enable jumbo (≥1550) on the underlay to raise overlay `mtu` to 1500;
  the UniFi static route for LAN reachability points `10.30.0.0/24 → 192.168.20.6` (pve01 exit node).
- **Apply ordering (bpg leading-finalizer pattern):** `sdn.tf` uses an empty
  `proxmox_sdn_applier.finalizer` (runs first, flushes pre-existing pending state) + a terminal
  applier (commits the staged stack). Adopted after the first apply hit an HTTP 500 swapping the
  Simple zone → EVPN under a shared id `talos`: Proxmox won't delete a zone a vnet still uses, and
  won't create a duplicate-id zone, and a partial apply left pending fabric/controller objects.
  **A zone-*type* change is not in-place** — the one-time migration requires a manual SDN teardown
  (subnet → vnet → zone → controller → fabric, then SDN Apply) + `terraform state rm` of the stale
  SDN resources, then a clean `apply`. The finalizer pattern makes that recreate (and future type
  changes / partial-apply recovery) self-healing.
- **Re-IP / dev-consumer code (landed 2026-06-08):** SDN applied successfully → started items #1–#3.
  Fixed `terraform/dev/main.tf` module `source` (`talos-pve-v3.1.0` → `talos-pve`, broken by the
  rename — would fail `init`); added `bridge = optional(string,"vmbr0")` to dev `var.pve` so `vtalos`
  is settable; updated the module `terraform.tfvars.example` to the `10.30.0.0/24` + `vtalos` +
  `pve01–pve06` pattern. **Remaining:** the SOPS-encrypted `terraform/dev/terraform.tfvars` edit
  (user-managed) — swap cluster networking `192.168.20.x → 10.30.0.x`, `pve.gateway → 10.30.0.1`,
  add `pve.bridge = "vtalos"`; plus the off-TF UniFi route + DNS (#4/#5). `pve.endpoint` stays on
  the mgmt LAN (`192.168.20.6`). Cluster is spun down → fresh apply, no in-place VM churn.
- **Future enhancement (unchanged):** once EVPN is healthy, optionally peer Cilium BGP with the
  Proxmox EVPN FRR to retire the in-overlay Cilium L2 announce.

## Implementation update — OpenFabric underlay removed; flat-L2 BGP-EVPN peers (2026-06-10)

The OpenFabric routed underlay from the 2026-06-08 note **does not work on this hardware** and was
removed. Root cause, confirmed on the live hosts during the first bootstrap attempt:

- FRR `fabricd` (OpenFabric) is **point-to-point only by design** — every circuit comes up as
  `Type: p2p` (`show openfabric interface detail`), hard-capped at `Active neighbors: 1`, with no
  broadcast/multi-access mode and no DIS election. OpenFabric targets spine-leaf Clos fabrics of
  p2p links.
- The fabric runs over the **shared `vmbr0` management L2** (six nodes on one switch). A p2p IGP
  cannot mesh a broadcast segment: each node held exactly one **flapping** adjacency (every neighbor
  showed the p2p placeholder SNPA `20:20:20:20:20:20`), so loopbacks `10.30.255.{7,9,10}` never
  propagated and **4 of 5 BGP-EVPN sessions stayed down** (`Connect`/`never`). Result: no overlay
  egress (Talos consoles stuck on `lookup … i/o timeout`) and no inbound path
  (`terraform … dial 10.30.0.20x:50000: i/o timeout`).
- Confirmed *not* the cause along the way: TrueNAS iSCSI, exit-node SNAT (`ip vrf exec vrf_talos
  ping 1.1.1.1` worked from the exit node), `vmbr0` MACs (unique), management L2 (corosync healthy).

**Fix (chosen):** drop the fabric entirely and use a **flat-L2 BGP-EVPN mesh** —
`proxmox_sdn_controller_evpn` with `peers = [<six mgmt IPs>]`, VTEP = each node's management IP, no
IGP/loopbacks. The management LAN already gives every node direct reachability to every other (the
same path corosync uses), so direct BGP peering is the correct and simplest control plane here. This
is the model Option B described *first*, before the 2026-06-08 note pivoted to the fabric form.

- **Repo changes (2026-06-10):** `terraform/proxmox-base/sdn.tf` — removed
  `proxmox_sdn_fabric_openfabric` + `proxmox_sdn_fabric_node_openfabric`; `proxmox_sdn_controller_evpn`
  now takes `peers` instead of `fabric`; applier deps trimmed. `variables.tf` — `var.sdn.evpn.fabric`
  (id/ip_prefix/nodes) replaced by `var.sdn.evpn.peers` (list of mgmt IPs) + matching validations. The
  SOPS-encrypted `terraform.tfvars` still needs the user edit (swap the `fabric { nodes {…} }` block
  for `peers = ["192.168.20.6", …, "192.168.20.11"]`).
- **Migration (zone/controller already live + broken):** changing the controller from `fabric` to
  `peers` and deleting the fabric resources is not fully in-place. Tear the SDN down once (subnet →
  vnet → zone → controller → **delete the OpenFabric fabric**, then **SDN → Apply**), `terraform
  state rm` any stale fabric/controller addresses, then a clean `apply`. The leading-finalizer in
  `sdn.tf` absorbs leftover pending state. Verify `vtysh -c 'show bgp l2vpn evpn summary'` shows all
  six peers `Established` **before** re-running the dev cluster apply.
- **If OSPF is ever wanted instead** (keep the loopback routed-underlay): the provider also ships
  `proxmox_sdn_fabric_ospf` / `_node_ospf`, and OSPF *does* support broadcast LANs (DR election).
  Rejected here as needless IGP complexity on a flat LAN, but it's the drop-in if a routed underlay
  becomes desirable.
- **Runbook:** the full teardown → apply → BGP-verify → UniFi-route → dev-apply → bootstrap procedure
  (with the anycast-source test caveat and the failure index) lives at
  [`_docs/runbooks/sdn-talos-rebuild.md`](../runbooks/sdn-talos-rebuild.md).

## Consequences

- **Phase 1 (A):** an apply-able single-host dev cluster on `vtalos`; proves the SDN/token/storage
  path; throwaway. Off-TF UniFi route (#4) + DNS (#5) must land first or the cluster is unreachable
  from the LAN.
- **Phase 2 (C):** kube-vip/LB + Cilium BGP become operated components; the UniFi/Proxmox routing
  config is **off-Terraform** and must be documented in a runbook. Removes the L2 gotchas from the
  ongoing bug surface.
- **Phase 2 (B, fallback):** an EVPN controller + exit node(s) to operate and monitor; the L2
  gotchas persist inside the overlay. The Simple zone is replaced (SDN re-apply).
- **All:** the cluster is on an isolated, SNAT'd subnet — external exposure consolidates onto
  Cloudflare Tunnel / Tailscale (already in place) rather than direct LAN reachability, which is a
  security improvement.

## Open items (before this becomes Accepted)

- **C blocker (researched 2026-06-08, see Research note above):** feasibility confirmed for the
  Talos+Cilium+UniFi stack, but cost is **gateway-model-dependent** — *low* on UDM/UXG-Enterprise
  (official UI BGP, persistent), *moderate* on a UCG (root-SSH FRR, non-persistent across firmware
  updates). **Confirm the exact gateway model**, then decide UniFi-peer-with-routed-subnet (a) vs
  Proxmox-FRR-peer (b) vs EVPN fallback. Resolve before Phase 2.
- Confirm exit-node strategy for B if it's chosen (single vs redundant exit nodes; the exit node
  is a routing SPOF otherwise).
- Decide the routed CP endpoint mechanism for C (kube-vip BGP vs external HAProxy vs UniFi VIP).
- Confirm `sdn.mtu` headroom for VXLAN if B is chosen (encap overhead vs the underlay MTU).
- **Storage across the SNAT boundary (OPEN, snat=true for now):** TrueNAS iSCSI `192.168.20.106:3260`
  (freshrss/authentik/gatus PVs via freenas-iscsi CSI) is reached from the cluster via exit-node SNAT,
  so initiators appear as the exit node's mgmt IP (`192.168.20.6`), not each node's `10.30.0.x`. Works
  if TrueNAS authorizes by IQN or by the `192.168.20.0/24` network; **breaks if it allows by specific
  old node IPs.** Verify TrueNAS iSCSI *Authorized Networks*/*Initiators* before the storage layer
  reconciles. Cleaner long-term fix if it bites: routed model (`sdn.snat=false` + UniFi route/NAT)
  preserves node IPs end-to-end. Also watch iSCSI-over-VXLAN MTU (jumbo the underlay → overlay 1500).

## Verification

- **Phase 1 (A):** `/terraform-plan` clean; apply produces a healthy single-host cluster; `kube dev
  get nodes` Ready; Cilium Gateway LB IP reachable on-host; kubeconfig exported to 1P (`memphis-kubeconfig`).
- **Phase 2 (C):** VIP/ARP gone from config; `cilium bgp peers` established with the upstream; LB IPs
  advertised as /32s and reachable cross-host; control-plane endpoint survives a CP-node reboot.
- **Phase 2 (B):** EVPN zone applied; a VM live-migrated to another host keeps its IP and L2; VIP fails
  over across hosts; Cilium L2 LB answers regardless of announcer-node host.
- **All:** `/lint` clean; the only tfvars diffs are the intended re-IP (#1–#3).
