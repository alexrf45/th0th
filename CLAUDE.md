# CLAUDE.md

## What this repo is

A GitOps-managed Kubernetes home lab to demonstrate various cloud native technologies, principles and best practices. Flux CD watches the `dev` branch of this repo and reconciles the cluster state. Talos Linux runs on Proxmox VMs provisioned by Terraform. Secrets are encrypted with SOPS (Age) and synced via 1Password Connect through the External Secrets Operator.

Once the dev branch has reached a user-defined state of maturity, it will be promoted to the main branch for the production cluster.

## Lab Goals & Requirements

The aim is to preside over a lab environment that is as close to production ready as possible with robust monitoring, observability, resilience, disaster recovery, alerting, best practices for cloud native security and network architecture. Services are exposed externally either via Tailscale, Cloudflare Tunnels or Ngrok. Services are exposed internally with the home-0ps.com domain.

Applications hosted in this environment should have a iOS mobile app equivalent or method to consume/interact with data from the cluster to extend and get the most out of the services. Users spend frequent time writing poetry, taking notes, saving links/articles and curating knowledge & media.

## Cluster access — REQUIRED

Always reference ./.claude/rules/kube-wrapper.md for proper interaction with the cluster

## Key commands

Runnable slash commands live in `.claude/commands/`:

| Command                  | Purpose                                      |
| ------------------------ | -------------------------------------------- |
| `/lint`                  | Run yamllint across the repo                 |
| `/flux-reconcile [name]` | Reconcile a Flux kustomization (or list all) |
| `/flux-status`           | Show state of all Flux resources             |
| `/cluster-health`        | Check pod and Talos node health              |
| `/terraform-plan`        | Init + plan the dev cluster                  |
| `/terraform-apply`       | Init + plan + apply the dev cluster          |

### Directory layout

| Directory     | Purpose                                                                                                                       |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `_clusters/`  | Cluster entrypoints — Flux reads `_clusters/<env>` to start reconciliation                                                    |
| `_lib/`       | Shared manifests, organized by deployment layer (controllers, pki, secrets, networking, dns, storage, security, applications) |
| `global/`     | CRDs applied across all clusters (Prometheus Operator, CNPG)                                                                  |
| `terraform/`  | Cluster provisioning (Talos on Proxmox, wallabag S3 backup infra)                                                             |
| `_templates/` | Boilerplate for HelmRelease, HelmRepository, Kustomization resources                                                          |
| `_hack/`      | One-off scripts and example YAML                                                                                              |
| `_docs/`      | Reviews, runbooks, migration notes                                                                                            |

# Business Rules & Documentation

Rules for conducting specific actions or design choices are located in the `./claude/rules` directory. Any new insights or requirements should be placed here as discovered.
