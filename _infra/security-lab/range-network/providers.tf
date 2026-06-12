# Reuses the proxmox-base two-phase auth pattern. Bootstrap as root@pam (leave
# pve_api_token empty); for day-to-day applies inject the least-privilege
# automation token created by terraform/proxmox-base via:
#   op run -- terraform apply
# with TF_VAR_pve_api_token set to terraform@pve!tf=<secret> (1Password).
provider "proxmox" {
  endpoint = "https://${var.pve.endpoint}:8006"
  insecure = true
  ssh {
    agent = false
  }

  api_token = var.pve_api_token != "" ? var.pve_api_token : null
  username  = var.pve_api_token == "" ? "root@pam" : null
  password  = var.pve_api_token == "" ? var.pve.password : null
}
