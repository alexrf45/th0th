# CLAUDE.md

## What this repo is

A **security research lab** (cyber range) built as reproducible Infrastructure as
Code on a 6-node Proxmox cluster. The lab is for practicing offensive **and**
defensive techniques, developing bespoke tools/payloads/detections for Linux and
Windows hosts, and testing CVEs — in network segments that are isolated at the
hypervisor level so detonating malware/payloads can never reach the home or
management network.

Environments are provisioned with **Terraform** (Proxmox SDN, RBAC, VMs) and
**Packer** (golden VM templates). Secrets are handled with the 1Password CLI and
SOPS. The range is VM-based and self-contained.

> History: this repo was previously a GitOps Kubernetes home lab (Flux/Talos). That
> tree (`_clusters/`, `_lib/`, `global/`, `_templates/`), the Talos cluster root
> (`dev`), and the `talos-pve` module have all been removed during the pivot.

## Lab goals & requirements

- Practice offensive + defensive cybersecurity; build detections for Linux/Windows.
- Test and understand CVEs and other vulnerabilities, with snapshot/rollback.
- Reproducible environments via Terraform + Packer (no click-ops for scenarios).
- **Hypervisor-level network segmentation** — detonation networks are air-gapped.
- **Storage split:** TrueNAS iSCSI holds **lab-administrative** data only (SIEM
  index, kept artifacts). Scenario/vulnerability disks live on **node-local**
  storage and never touch the NAS.

## Start here

The security range is built in phases. The entry point is the bring-up runbook:

- **`_docs/runbooks/security-lab-bring-up.md`** — master Phase 0→2 checklist +
  current build status.
- **`_docs/decisions/0009-security-lab-segmentation.md`** — the design (ADR).
- **`.claude/rules/lab-isolation.md`** — non-negotiable safety invariants. **Read
  before any change to range networking, the `scenario-vm` module, or a scenario.**

## Directory layout

| Directory                     | Purpose                                                                                                                                                            |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_infra/terraform/`           | Terraform: `modules/` (`proxmox-base`, `scenario-vm`); `security-lab/` (`range-network` shared plumbing [S3 state] + `scenarios/<name>` disposable labs [local state]) |
| `_infra/packer/`              | Packer golden-image builds → node-local templates (ubuntu, kali, windows-server/10/11)                                                                            |
| `_docs/`                      | Deployment info + insights: `decisions/` (ADRs), `runbooks/`, `reviews/`, `prerequisites.md`                                                                       |
| `_hack/`                      | One-off scripts, utilities, and example YAML (yours or ours)                                                                                                       |
| `.claude/rules/`              | Business rules (see below)                                                                                                                                         |
| `.claude/commands/`           | Runnable slash commands                                                                                                                                            |

## How infrastructure is run

- **Terraform and Packer are run by you, manually, wrapped in the 1Password CLI**:
  `op run -- terraform apply`, `op run -- packer build …`. Claude does not run
  `apply`/`build`. Bare `terraform`/`packer` under the `op` plugin fail with
  `interactive IO not available` (that's expected — use `terraform validate` /
  `packer validate` for offline checks).
- **State:** shared/persistent range plumbing (SDN, firewall) uses the **S3**
  backend; each disposable scenario uses **local** state. A wiped/compromised
  scenario must never corrupt shared infrastructure state.
- **Secrets:** `terraform.tfvars`, `remote.tfbackend`, and Packer var-files are
  **SOPS-encrypted** before commit. Never modify SOPS/secret files without explicit
  user confirmation.

## Business rules & documentation

Rules for specific actions or design choices live in **`.claude/rules/`**. Add new
insights/requirements there as discovered. Key ones:

- **`lab-isolation.md`** — the range's safety invariants (air-gap, node-local disks,
  one-way telemetry). Highest priority for any range change.
- **`terraform-buisness-rules.md`** — fetch live provider docs, S3-vs-local state,
  `op`-wrapped applies, SOPS, prefer defaults.
- **`secrets.md`** — secret handling; never pipe live credentials or re-encrypt SOPS
  files without confirmation.
- **`lab_architecture.md`** — hardware inventory (Proxmox nodes, UniFi, TrueNAS).
- **`code.md`**, **`yaml-conventions.md`**, and the `*-review.md` rules — code/doc
  quality and review criteria.

## Key commands

Runnable slash commands live in `.claude/commands/`:

| Command | Purpose                                                                   |
| ------- | ------------------------------------------------------------------------- |
| `/lint` | `fmt`-check + `validate` Terraform & Packer (`_hack/scripts/iac-lint.sh`)  |
