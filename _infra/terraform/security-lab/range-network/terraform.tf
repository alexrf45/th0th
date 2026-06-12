terraform {
  required_version = ">= 1.10.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.107.0"
    }
  }

  # Shared, persistent range plumbing (VLAN zones + cluster firewall) keeps S3
  # remote state — per .claude/rules/terraform-buisness-rules.md, infrastructure
  # uses the S3 backend; only disposable per-scenario roots use local state.
  # Backend is partially configured: `terraform init -backend-config=remote.tfbackend`.
  backend "s3" {}
}
