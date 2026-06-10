# EVPN SDN — ADR-0008 Option B. Replaces the former Simple zone.
#
# Stretched-L2 VXLAN overlay across all PVE hosts so the multi-host HA Talos
# cluster keeps its control-plane VIP + Cilium L2 LoadBalancer design. The
# underlay is a PVE 9 OpenFabric (IS-IS) routed fabric: each node advertises a
# loopback router-id and EVPN VXLAN tunnels run loopback-to-loopback.
#
# Apply ordering uses the bpg leading-finalizer pattern:
#   1. proxmox_sdn_applier.finalizer  — commits/flushes any PRE-EXISTING pending
#      SDN state before we stage anything (a partial prior apply leaves pending
#      fabric/controller objects that otherwise collide on create -> HTTP 500).
#   2. all SDN objects stage as "pending" (rooted after the finalizer).
#   3. proxmox_sdn_applier.this       — terminal commit of the staged objects.

# Leading applier: empty + no depends_on so it runs first and clears pending.
resource "proxmox_sdn_applier" "finalizer" {}

# ── Underlay: OpenFabric routed fabric ──────────────────────────────────────
# IS-IS adjacencies form over evpn.fabric.nodes[*].interfaces (vmbr0 here, the
# flat management L2). Each node gets a /32 loopback from fabric.ip_prefix.
resource "proxmox_sdn_fabric_openfabric" "this" {
  id        = var.sdn.evpn.fabric.id
  ip_prefix = var.sdn.evpn.fabric.ip_prefix

  depends_on = [proxmox_sdn_applier.finalizer]
}

resource "proxmox_sdn_fabric_node_openfabric" "this" {
  for_each        = var.sdn.evpn.fabric.nodes
  fabric_id       = proxmox_sdn_fabric_openfabric.this.id
  node_id         = each.key              # PVE node name, e.g. "pve01"
  ip              = each.value.ip         # loopback router-id
  interface_names = each.value.interfaces # IGP interface(s) on this node
}

# ── Control plane: EVPN (BGP) over the fabric loopbacks ─────────────────────
# Peers are auto-discovered via the fabric, so no explicit peer list is needed.
resource "proxmox_sdn_controller_evpn" "this" {
  id     = var.sdn.evpn.controller_id
  asn    = var.sdn.evpn.asn
  fabric = proxmox_sdn_fabric_openfabric.this.id

  depends_on = [proxmox_sdn_applier.finalizer]
}

# ── Overlay: EVPN zone (stretched L2 + anycast L3 + exit-node SNAT) ──────────
# vrf_vxlan is the routing VRF VNI; it MUST differ from the vnet tag below.
# exit_nodes carry L3 egress out of the overlay; list >1 to avoid a routing SPOF.
resource "proxmox_sdn_zone_evpn" "this" {
  id         = var.sdn.zone_id
  nodes      = coalesce(var.sdn.nodes, var.pve.hosts)
  controller = proxmox_sdn_controller_evpn.this.id
  vrf_vxlan  = var.sdn.evpn.vrf_vxlan
  mtu        = var.sdn.mtu

  exit_nodes               = var.sdn.evpn.exit_nodes
  primary_exit_node        = var.sdn.evpn.primary_exit_node
  exit_nodes_local_routing = true
  advertise_subnets        = var.sdn.evpn.advertise_subnets
  ipam                     = "pve"
}

# The VNet — its id becomes the bridge name VMs attach to (network_device.bridge).
# tag is the per-vnet VXLAN VNI and must differ from the zone vrf_vxlan.
resource "proxmox_sdn_vnet" "this" {
  id   = var.sdn.vnet_id
  zone = proxmox_sdn_zone_evpn.this.id
  tag  = var.sdn.evpn.vnet_tag
}

# Anycast gateway (present on every node) + SNAT egress via the exit node(s).
# Static addressing only (Talos/cloud-init sets node IPs) — no DHCP range.
resource "proxmox_sdn_subnet" "this" {
  vnet    = proxmox_sdn_vnet.this.id
  cidr    = var.sdn.subnet_cidr
  gateway = var.sdn.gateway
  snat    = var.sdn.snat
}

# Terminal applier: commits all staged SDN objects in one shot. depends_on the
# whole stack so the commit runs last; replace_triggered_by re-commits whenever
# any SDN object changes on later applies.
resource "proxmox_sdn_applier" "this" {
  depends_on = [
    proxmox_sdn_applier.finalizer,
    proxmox_sdn_fabric_openfabric.this,
    proxmox_sdn_fabric_node_openfabric.this,
    proxmox_sdn_controller_evpn.this,
    proxmox_sdn_zone_evpn.this,
    proxmox_sdn_vnet.this,
    proxmox_sdn_subnet.this,
  ]

  lifecycle {
    replace_triggered_by = [
      proxmox_sdn_fabric_openfabric.this,
      proxmox_sdn_controller_evpn.this,
      proxmox_sdn_zone_evpn.this,
      proxmox_sdn_vnet.this,
      proxmox_sdn_subnet.this,
    ]
  }
}
