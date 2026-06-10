variable "pve" {
  description = "Proxmox VE connection + node inventory. `hosts` are the PVE node names the SDN zone is deployed to."
  type = object({
    endpoint = string
    password = string
    hosts    = list(string)
  })
  sensitive = true
}

variable "pve_api_token" {
  description = <<-EOT
    Phase-2 cutover token in the form `user@realm!tokenname=secret`. Leave empty
    to bootstrap as root@pam (Phase 1). Inject via TF_VAR_pve_api_token / op run
    after the automation token has been created and published to 1Password.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "op_service_account_token" {
  description = "1Password service account token with write access to the vault (same one terraform/dev uses to export kubeconfig)."
  type        = string
  sensitive   = true
}

variable "op_vault_id" {
  description = "1Password vault UUID for infrastructure secrets (where the automation token item is written and the admin password item is read)."
  type        = string
}

variable "admin" {
  description = <<-EOT
    Day-to-day Proxmox admin. granted the built-in PVEAdmin role at /. The
    password is READ from a pre-created 1Password item — never hardcoded — so it
    stays rotatable.
  EOT
  type = object({
    user_id       = optional(string, "admin@pve")
    op_item_title = string # 1P item holding the admin password
    comment       = optional(string, "Day-to-day admin (managed by terraform/proxmox-base)")
  })
}

variable "automation" {
  description = "Least-privilege Terraform automation principal (@pve) + API token that replaces root@pam in the provider blocks."
  type = object({
    user_id       = optional(string, "terraform@pve")
    role_id       = optional(string, "terraform")
    token_name    = optional(string, "tf")
    op_item_title = optional(string, "proxmox-terraform-token") # 1P item the token is written to
    comment       = optional(string, "Terraform automation (managed by terraform/proxmox-base)")
  })
  default = {}
}

variable "sdn" {
  description = <<-EOT
    EVPN SDN zone (ADR-0008 Option B) for the HA Talos cluster. A VXLAN overlay
    stretches L2 across all PVE hosts — restoring the Talos control-plane VIP and
    the Cilium L2 LoadBalancer design — with an anycast gateway + exit-node SNAT
    for egress. The underlay is a PVE 9 OpenFabric (IS-IS) routed fabric: each
    node gets a loopback router-id from evpn.fabric.ip_prefix and EVPN VXLAN
    tunnels run loopback-to-loopback (no flat-L2 BGP peer list). Use a subnet
    that does NOT overlap the LAN (192.168.20.0/24).
  EOT
  type = object({
    zone_id     = optional(string, "talos")  # PVE SDN id, max 8 chars
    vnet_id     = optional(string, "vtalos") # PVE SDN id, max 8 chars
    subnet_cidr = string                     # e.g. "10.30.0.0/24"
    gateway     = string                     # anycast gateway, e.g. "10.30.0.1"
    snat        = optional(bool, true)
    nodes       = optional(list(string))   # zone node set; defaults to var.pve.hosts
    mtu         = optional(number, 1450)   # VXLAN overlay: 1500 underlay - 50B encap

    evpn = object({
      controller_id     = optional(string, "evpn")
      asn               = number                  # EVPN/underlay ASN (private 64512-65534)
      vrf_vxlan         = optional(number, 4000)  # VRF VNI — MUST differ from vnet_tag
      vnet_tag          = optional(number, 10300) # per-vnet VXLAN VNI
      exit_nodes        = list(string)            # PVE host(s) providing L3 egress + SNAT
      primary_exit_node = optional(string)        # active exit node; others standby
      advertise_subnets = optional(bool, true)

      # Routed underlay (PVE 9 SDN fabric). OpenFabric/IS-IS distributes per-node
      # loopbacks; EVPN rides on top instead of a flat-L2 BGP peer mesh.
      fabric = object({
        id        = optional(string, "talosfab")       # <= 8 chars
        ip_prefix = optional(string, "10.30.255.0/24") # underlay loopbacks; NOT the VM subnet or LAN
        nodes = map(object({          # key = PVE node name (must be in var.pve.hosts)
          ip         = string         # node loopback from ip_prefix, e.g. "10.30.255.6"
          interfaces = list(string)   # IGP interface(s) facing peers, e.g. ["vmbr0"]
        }))
      })
    })
  })
  validation {
    condition     = can(cidrnetmask(var.sdn.subnet_cidr))
    error_message = "sdn.subnet_cidr must be a valid CIDR (e.g. 10.30.0.0/24)."
  }
  validation {
    condition     = cidrhost("${var.sdn.gateway}/${split("/", var.sdn.subnet_cidr)[1]}", 0) == cidrhost(var.sdn.subnet_cidr, 0)
    error_message = "sdn.gateway must be inside sdn.subnet_cidr."
  }
  validation {
    condition     = cidrhost(var.sdn.subnet_cidr, 0) != "192.168.20.0"
    error_message = "sdn.subnet_cidr must not reuse the LAN 192.168.20.0/24 — the overlay needs its own isolated subnet."
  }
  validation {
    condition     = var.sdn.evpn.vrf_vxlan != var.sdn.evpn.vnet_tag
    error_message = "sdn.evpn.vrf_vxlan (VRF VNI) must differ from sdn.evpn.vnet_tag (vnet VNI) — Proxmox rejects equal VNIs."
  }
  validation {
    condition     = length(var.sdn.evpn.exit_nodes) > 0
    error_message = "sdn.evpn.exit_nodes must list at least one PVE host for egress/SNAT."
  }
  validation {
    condition     = can(cidrnetmask(var.sdn.evpn.fabric.ip_prefix)) && cidrhost(var.sdn.evpn.fabric.ip_prefix, 0) != cidrhost(var.sdn.subnet_cidr, 0)
    error_message = "sdn.evpn.fabric.ip_prefix must be a valid CIDR that does not overlap sdn.subnet_cidr."
  }
  validation {
    condition     = alltrue([for n in var.sdn.evpn.fabric.nodes : cidrhost("${n.ip}/${split("/", var.sdn.evpn.fabric.ip_prefix)[1]}", 0) == cidrhost(var.sdn.evpn.fabric.ip_prefix, 0)])
    error_message = "Every sdn.evpn.fabric.nodes[*].ip must fall inside sdn.evpn.fabric.ip_prefix."
  }
}
