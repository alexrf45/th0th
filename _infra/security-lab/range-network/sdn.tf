# Security-range network segmentation — ADR-0009.
#
# A single Proxmox SDN VLAN zone backed by vmbr0. Each vnet maps to an 802.1Q
# VLAN tag carried over the UniFi switch trunk, giving TRUE cross-node L2 (a DC on
# pve01 and a workstation on pve04 share a broadcast domain). The zone provides no
# gateway, so isolation is structural:
#
#   - ops VLAN  : its gateway/SVI lives on the UCG (firewalled, WAN allow-list).
#   - detonation: NO SVI anywhere, NO Proxmox subnet -> a gateway-less L2 island.
#                 A fully compromised victim has no L3 next-hop off its segment;
#                 the only bridges in are deliberately dual-homed ops boxes
#                 (Kali, Wazuh) that also carry a NIC on the detonation vnet.
#
# Apply ordering reuses the proxmox-base leading-finalizer pattern: flush any
# pre-existing pending SDN state, stage objects, then commit once at the end.
# This root owns its own appliers; SDN apply is cluster-global but idempotent and
# only commits already-staged objects, so it does not fight terraform/proxmox-base.

resource "proxmox_sdn_applier" "finalizer" {}

resource "proxmox_sdn_zone_vlan" "lab" {
  id     = var.lab_sdn.zone_id
  bridge = var.lab_sdn.bridge
  nodes  = coalesce(var.lab_sdn.nodes, var.pve.hosts)
  mtu    = var.lab_sdn.mtu
  ipam   = "pve"

  depends_on = [proxmox_sdn_applier.finalizer]
}

# Ops/admin network (Kali, Wazuh, C2, orchestration). Gateway is the UCG SVI for
# this VLAN — never defined here — with a WAN allow-list and no route to the
# management LAN.
resource "proxmox_sdn_vnet" "ops" {
  id   = var.lab_sdn.ops.vnet_id
  zone = proxmox_sdn_zone_vlan.lab.id
  tag  = var.lab_sdn.ops.vlan
}

# Detonation networks — one gateway-less L2 island per scenario. isolate_ports
# stays false on purpose: victims must reach each other (DC <-> workstation,
# LLMNR/NBT-NS/mDNS poisoning) — the air-gap is the missing gateway, not port
# isolation. Do NOT add a proxmox_sdn_subnet or a UCG SVI for these VLANs.
resource "proxmox_sdn_vnet" "detonation" {
  for_each = var.lab_sdn.detonation

  id   = each.value.vnet_id
  zone = proxmox_sdn_zone_vlan.lab.id
  tag  = each.value.vlan
}

resource "proxmox_sdn_applier" "this" {
  depends_on = [
    proxmox_sdn_applier.finalizer,
    proxmox_sdn_zone_vlan.lab,
    proxmox_sdn_vnet.ops,
    proxmox_sdn_vnet.detonation,
  ]

  lifecycle {
    replace_triggered_by = [
      proxmox_sdn_zone_vlan.lab,
      proxmox_sdn_vnet.ops,
      proxmox_sdn_vnet.detonation,
    ]
  }
}
