# talos-pve module — sprint tracker

Living checklist for the `terraform/modules/talos-pve-v3.1.0` refactor. Rationale
and the full findings catalogue live in the decision record,
[ADR-0006](decisions/0006-talos-pve-module-refactor.md) (Option B, exact pins);
this page tracks **status only**. Update the status column as sprints land.

| #  | Sprint                              | Status       |
| -- | ----------------------------------- | ------------ |
| 1  | Dependencies & provider hygiene     | Done (2026-05-24) |
| 2  | Variable & doc consistency          | Done (2026-05-24) |
| 3  | Hardcoded values & latent bugs      | Done (2026-05-24) |
| 4  | Talos config modernization          | Done (2026-05-24) |
| 5  | GPU passthrough                     | Deferred     |
| 6  | Node-label apply-ordering           | Deferred — investigate |

## Done

- **Sprint 1 — Dependencies & provider hygiene.** Exact-pin all providers in both
  `modules/talos-pve-v3.1.0/terraform.tf` and `terraform/dev/terraform.tf`; remove dead
  `local`; `required_version >= 1.10.0`; migrate root `kubernetes_secret` →
  `kubernetes_secret_v1`; fix example source path + worker memory `8092`→`8192`.
- **Sprint 2 — Variable & doc consistency.** Reconcile module↔dev variable drift, port the 4
  validations, align `talos.name`/`kube_version`; refresh `README.md`; unify the example
  bootstrap pattern.
- **Sprint 3 — Hardcoded values & latent bugs.** Derive netmask from `node_network`;
  parameterize the 2nd disk device; split the CoreDNS internal forwarder into its own variable.
- **Sprint 4 — Talos config modernization.** Talos OS → **v1.12.8** (k8s **1.35**) + **cilium
  1.19.4**; `config_patches` DRY'd via `local.machine_common` (render-identical, no node-set
  dependency); UserVolumeConfig + ephemeral resources deferred. Follow-up fix: pinned
  `kubernetes_version` on both `talos_machine_configuration` data sources (the 0.11 provider
  otherwise defaulted to 1.36.0, rejected by Talos 1.12.8).

## Deferred

- **Sprint 5 — GPU passthrough (future module version).** Optional per-node `hostpci`/VFIO;
  verify proxmox 0.107 `hostpci`/`pcie` support; gated by a variable. Ties to
  [ADR-0004](decisions/0004-gpu-vfio-passthrough.md); needs hardware validation.
- **Sprint 6 — Node-label apply-ordering (investigate).** `kubernetes_labels.worker_role`
  errors on the **initial** apply (kubeconfig/node not ready when labels run) but succeeds on
  re-apply — and the failure **blocks the rest of the deployment**, so a re-apply is currently
  required. This is finding #15 (kubernetes provider configured from `module.dev.*` outputs +
  in-module `kubernetes_labels`) materializing. Candidate fixes: stronger
  `depends_on`/readiness wait, set labels via the Talos machine config (`machine.nodeLabels`)
  instead of a post-bootstrap `kubernetes_labels` resource, or the two-stage apply from #15.
  Goal: clean first-apply, no manual retry.
