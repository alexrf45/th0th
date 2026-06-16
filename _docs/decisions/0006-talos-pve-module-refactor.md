# ADR-0006: talos-pve module — refactor scope + provider upgrades

- **Status:** Accepted (2026-05-24) — **Option B** chosen; **exact** version pins; GPU passthrough deferred to a future module version. Sprinted below.
- **Date:** 2026-05-24
- **Deciders:** fr3d (with Claude review)
- **Related:** [ADR-0004](0004-gpu-vfio-passthrough.md) (its open items reference the pinned `bpg/proxmox` provider's `hostpci` support — relevant to whichever upgrade lands here).

## Context

The dev cluster was spun down on 2026-05-23.
With no live VMs, the next `terraform apply` is a **greenfield rebuild** — the
cheapest possible window to take large provider jumps, since there are no in-place
diffs against running infrastructure to churn or destroy.

Two things forced this review now:

1. **The module move is half-finished.** Commit `eb3faf0` relocated the module
   from `terraform/dev/talos-pve-v3.1.0/` → `terraform/modules/talos-pve-v3.1.0/`
   "to reduce duplication", but `terraform/dev/main.tf` still points at
   `source = "./talos-pve-v3.1.0"`. That path no longer exists, so
   **`terraform init` is currently broken.** (`.terraform/modules/modules.json`
   still caches the dead path.) **user fixed path and removed .teraform dir**
2. **Provider drift has accumulated** — most notably `bpg/proxmox` is 14 minor
   releases behind and a `hashicorp/kubernetes` major version is available.

## Provider upgrade landscape (registry-verified, 2026-05-24)

| Provider              | Constraint             | Locked | Latest stable | Note                                  |
| --------------------- | ---------------------- | ------ | ------------- | ------------------------------------- |
| bpg/proxmox           | `~> 0.93.0`            | 0.93.1 | **0.107.0**   | 14 minors behind; pre-1.0, moves fast |
| siderolabs/talos      | `0.10.1` / `~> 0.10.1` | 0.10.1 | **0.11.0**    | 0.12 is alpha — skip                  |
| hashicorp/kubernetes  | `~> 2.36.0`            | 2.36.0 | **3.1.0**     | **major (2→3)**                       |
| hashicorp/helm        | `~> 3.0.0`             | 3.0.2  | 3.1.2         | minor                                 |
| fluxcd/flux           | `1.7.6`                | 1.7.6  | 1.8.8         | 1 minor behind                        |
| 1Password/onepassword | `3.2.1`                | 3.2.1  | 3.3.1         | minor                                 |
| hashicorp/random      | `~> 3.7.0`             | 3.7.2  | current       | fine                                  |
| hashicorp/time        | `~> 0.11.0`            | 0.11.2 | current       | fine                                  |
| hashicorp/local       | `~> 2.5.0`             | 2.5.3  | —             | **unused → remove**                   |
| hashicorp/aws         | _(unconstrained)_      | 6.46.0 | —             | **floating → pin or drop**            |

- **kubernetes 2→3** (v3.0.0, Dec 2025): deps bumped to k8s 1.33; many resources
  _deprecated_ toward `_v1`-suffixed names (`kubernetes_secret` → `kubernetes_secret_v1`)
  — deprecations, not removals, so current code keeps working. `kubernetes_labels`
  (the module's only k8s resource) is unaffected. **Low risk for our usage.**
- **proxmox 0.93→0.107**: breaking entries in range (power-state centralisation,
  computed `cpu.units`, VM-datasource deprecation) don't touch attributes the module
  uses, and are moot against empty state.

## Findings catalogue

**Correctness — must-fix in every option**

1. `terraform/dev/main.tf` `source` → broken; fix to `../modules/talos-pve-v3.1.0`.
2. `example/main.tf` `source = "./talos-pve-v3.1.0"` → broken (it's inside the module); fix to `../`.
3. Dead `local` provider in module `terraform.tf` (config-export uses 1Password now).
4. Floating, unpinned `aws` provider in dev + empty `provider "aws" {}` block — pin or drop.
5. `dev/variables.tf` worker `memory` default typo `8092` → `8192`.

**Drift / duplication** 6. Module `variables.tf` vs `dev/variables.tf` diverged: `talos.name`
(`cluster` vs `k8s-cluster`), cilium `kube_version` (`1.35.0` vs `1.33.0`), and
4 validations (subnet CIDRs, `cluster_dns_ip ∈ service_subnet`, `vip_ip`/node IPs
`∈ node_network`) exist only in the module. 7. `README.md` is stale — documents `local_sensitive_file` exports and
`tls`/`local`/flux `~> 1.5.0` that the code no longer uses (config-export writes
to **1Password**). 8. Two divergent SOPS-age bootstrap impls: `example/main.tf` reads from a file,
`dev/main.tf` reads from a 1Password data source.

**DRY / maintainability** 9. `talos_machine_configuration.controlplane`/`.worker` config_patches are ~80%
identical heredocs → extract a shared base with role deltas. Biggest single win;
cuts drift risk on Talos version bumps (the CoreDNS `.:53` block already needs
manual re-sync per the in-file note). 10. CP/worker `proxmox_virtual_environment_vm` blocks are ~95% identical — optional
to unify; separate resources preserve the v3.0.0 independent-scaling design.

**Hardcoded / latent bugs** 11. `pve.tf` hardcodes `/24` in `ip_config` while `node_network` is a configurable CIDR. 12. `talos.tf` hardcodes the 2nd disk device `/dev/vdb` (install disk is a var). 13. CoreDNS split-horizon forwarder overloads `var.nameservers.secondary` as **both**
the public node fallback **and** the internal `th0th.dev` forwarder — and its
default is `8.8.8.8`, so if ever left at default, internal split-horizon DNS
silently breaks. Give the internal forwarder its own variable.

**Structure** 14. Version-in-directory-name antipattern (`talos-pve-v3.1.0`) → version via git tags + CHANGELOG. 15. `kubernetes`/`flux` providers configured from `module.dev.*` outputs + in-module
`kubernetes_labels` → apply-time-ordering foot-gun; can't cleanly plan before the
cluster exists. 16. `terraform/production/` is empty though env validation allows dev/staging/prod.

## Options

### Option A — Patch & safe-pin _(low risk, ~½ day)_

Findings #1–5 + README refresh (#7). Within-major bumps only: talos→0.11.0,
helm→`~> 3.1`, flux→`~> 1.8`, onepassword→`~> 3.3`. **Keep** proxmox `~> 0.93`
and kubernetes `~> 2.36`. Outcome: module init/applies again; no structural change.
Leaves the proxmox + kubernetes debt to compound.

### Option B — Refactor + full modernization ("v3.2.0") _(medium risk, 1–2 days)_ — **recommended**

Everything in A, **plus**: DRY the machine-config heredocs (#9); reconcile the
duplicated variables + port the missing validations (#6); parameterize netmask &
disk device (#11, #12); split the CoreDNS forwarder into its own variable (#13);
collapse the example onto one canonical bootstrap pattern (#2, #8). **Full** upgrades
to latest stable incl. **proxmox → `~> 0.107`** and **kubernetes → `~> 3.1`**
(migrate `kubernetes_secret` → `kubernetes_secret_v1`), with standardized `~>` constraints.

### Option C — Restructure to a reusable, multi-env module _(higher risk, several days)_

Everything in B, **plus**: rename to `talos-pve` with git-tag versioning + CHANGELOG
(#14); formalise a two-stage apply (cluster → kubeconfig → bootstrap/labels) to remove
the provider-from-output foot-gun (#15); add staging/prod consumer scaffolds (#16);
optionally unify CP/worker VM resources (#10) and adopt a remote module source.
Most production-ready (matches the lab's stated "as close to production as possible"
goal); most churn and a changed apply workflow.

## Recommendation: Option B

The cluster is down, so the proxmox (14-version) and kubernetes (major) jumps are as
cheap as they will ever be — a fresh apply has no live VMs to churn, so validation is
simply "does `/terraform-plan` then apply produce a healthy cluster." B clears the
real correctness bugs **and** the maintainability traps (duplicated heredocs, drifted
vars, overloaded DNS var) without committing to C's workflow change and naming churn,
which can be a follow-up ADR once B is proven.

**Prior-preference flag:** talos/flux/onepassword are currently pinned _exactly_ while
everything else uses `~>`. B proposes standardizing on `~>` for consistency — flagged
because it changes that choice; keep exact pins if strict reproducibility is preferred.
**Decision: keep exact pins** (user) — pin every provider to an exact version.

## Decision (accepted 2026-05-24)

**Option B**, exact pins, executed as the sprints below.

- **Already closed by user (pre-work):** #1 module source path fixed + stale
  `.terraform` removed; #4 empty `aws` provider block dropped from `terraform/dev`;
  state confirmed empty (S3 bucket exists, no state) → genuine greenfield.
- **Pin style:** exact versions for all providers (latest stable, 2026-05-24):
  proxmox `0.107.0`, talos `0.11.0`, kubernetes `3.1.0`, helm `3.1.2`, flux `1.8.8`,
  onepassword `3.3.1`, random `3.7.2`, time `0.11.2`; `local` removed.
- **DRY caveat (Sprint 4):** config_patches de-duplication must preserve **independent
  node scaling** — identical render for unchanged nodes, no dependency on the node set.
  Prefer `local` literal-fragment extraction over `templatefile()`. If byte-identical
  render isn't guaranteed, keep the duplication.
- **GPU (Sprint 5, deferred):** add optional `hostpci` VFIO passthrough to the VM
  resources to future-proof for hardware upgrades — ties to [ADR-0004](0004-gpu-vfio-passthrough.md);
  needs hardware validation, so it lands as a separate future module version.
- **Talos findings (drives Sprint 4):** provider 0.11 bundles Talos SDK **v1.13** and
  adds **ephemeral resources** (opportunity to stop persisting kubeconfig/talosconfig in
  state). Latest Talos OS is **v1.13**; module runs **v1.10.6**. Legacy `machine.disks`
  (the `/var/data` second-disk mount) → modern **`UserVolumeConfig`** document is the
  main syntax-modernization opportunity the user asked us to evaluate.

## Sprint plan (Option B)

_Live status is tracked in [talos-pve-module-sprints.md](../talos-pve-module-sprints.md); this section holds the plan + rationale._

_Progress: Sprints 1–4 done (2026-05-24). Sprint 4 decisions: Talos OS → **v1.12.8** (k8s
1.35) + **cilium 1.19.4** (1.13/k8s-1.36 dropped — no stable cilium supports k8s 1.36),
`config_patches` DRY'd via `local.machine_common`, UserVolumeConfig + ephemeral resources
deferred. Sprint 5 deferred. **Re-validate with `terraform plan` before apply.**_

- **Sprint 1 — Dependencies & provider hygiene.** Exact-pin all providers (above) in
  both `modules/talos-pve-v3.1.0/terraform.tf` and `terraform/dev/terraform.tf`; remove
  dead `local`; align `required_version` to `>= 1.10.0`. Migrate root `kubernetes_secret`
  → `kubernetes_secret_v1` (k8s provider 3.x). Fix #2 (example source `../`), #5 (worker
  memory `8092`→`8192` in `dev/variables.tf` + module tfvars.example). Then user runs
  `init -upgrade` + `/terraform-plan`.
- **Sprint 2 — Variable & doc consistency.** Reconcile module↔dev variable drift (#6,
  port the 4 validations + align `talos.name`/`kube_version`); refresh `README.md` (#7);
  unify the example bootstrap pattern + drop stale `config_export` fields (#8).
- **Sprint 3 — Hardcoded values & latent bugs.** Derive netmask from `node_network`
  (#11); parameterize 2nd disk device (#12); split the CoreDNS internal forwarder into
  its own variable, decoupled from `nameservers.secondary` (#13).
- **Sprint 4 — Talos config modernization.** Adopt `UserVolumeConfig` for `/var/data`;
  evaluate ephemeral resources for kube/talosconfig; **carefully** DRY config_patches per
  the caveat above; evaluate OS bump 1.10.6 → 1.11/1.13 (tfvars-level, recommend not force).
- **Sprint 5 — GPU passthrough (future module version, deferred).** Optional per-node
  `hostpci`/VFIO; verify proxmox 0.107 `hostpci`/`pcie` support; gated by a variable.
- **Sprint 6 — Node-label apply-ordering (deferred, investigate).** `kubernetes_labels.worker_role`
  errors on the **initial** apply (kubeconfig/node not ready when labels run) but succeeds on
  re-apply — and the failure blocks the rest of the deployment. This is finding #15 (provider
  configured from `module.dev.*` outputs, in-module `kubernetes_labels`) materializing. Investigate
  a real ordering fix: stronger `depends_on`/readiness wait, set node labels via the Talos
  machine config (`machine.nodeLabels`) instead of a post-bootstrap `kubernetes_labels` resource,
  or the two-stage apply from #15. Goal: clean first-apply, no manual retry.

Structural items #14 (drop version-in-dirname), #15 (two-stage apply), #16 (staging/prod
scaffolds) stay out of scope (Option C) — revisit in a follow-up ADR once B is proven.

## Sprint 4 — findings & recommendations (2026-05-24)

Talos↔k8s: 1.10→k8s 1.33 (current), 1.11→1.34, 1.12→1.35, 1.13→1.36. Latest stable is
1.13.x; provider 0.11 bundles Talos SDK 1.13. Module is on **v1.10.6 / kube_version 1.33.0**
(already aligned). Source: docs.siderolabs.com, talos.dev release discussions.

1. **UserVolumeConfig — defer; keep `machine.disks`.** `machine.disks` is deprecated but
   still supported through 1.13. UserVolumeConfig mounts at `/var/mnt/<name>` (not an
   arbitrary path), so moving `/var/data` would force coordinated changes to the kubelet
   mount **and** the GitOps storage layer (local-path provisioner / freenas-iscsi paths).
   Do it deliberately as its own change once storage paths are audited — not in this refactor.
2. **Ephemeral resources (provider 0.11) — do not adopt.** They'd keep kubeconfig/talosconfig
   out of state, but Terraform forbids feeding an ephemeral value into a persistent resource,
   which breaks `config-export.tf`'s `onepassword_item` export that the `kube`/`k8sop` wrapper
   depends on. Keep the persist-to-1Password design. (Optional minor cleanup: drop the redundant
   `kubeconfig`/`talos_config` module outputs — 1P is the source of truth — but keep the
   `kubernetes_*` provider-config outputs.)
3. **Talos OS bump — decision needed.** Greenfield + provider already on SDK 1.13 make it cheap,
   but it changes the cluster k8s version (→ all GitOps workloads), so it's a cluster-wide call.
   Latest **1.13.x (k8s 1.36)** for currency if workload API-compat is reviewed; conservative
   step **1.11.x (k8s 1.34)**. `cilium_config.kube_version` must follow.
4. **DRY `config_patches` — proposed, needs validation.** Extract the identical `machine:`
   sub-tree (systemDiskEncryption→disks) into a shared `local` literal fragment; keep
   role-specific `install.image`/`network` inline. No dependency on the node set → scaling
   stays per-node ([[feedback-dry-vs-node-scaling]]). Must be validated with `terraform
   validate`/`plan` (1P-wrapped, user-run) before apply — render-equivalence can't be checked
   in this environment.

**Decisions taken (2026-05-24):** OS → **v1.12.8** (k8s 1.35), `kube_version` → `1.35.0`,
`cilium_version` → **1.19.4** (was 1.18.0) in defaults + tfvars examples; DRY **implemented**
(`local.machine_common`, render-identical, no node-set dependency). UserVolumeConfig +
ephemeral **deferred**.

> **Why not 1.13/k8s 1.36:** no stable cilium supports k8s 1.36 (cilium 1.19.4 e2e-tests up
> to k8s 1.35; pinned 1.18.0 only reached k8s 1.33). Since the module bootstraps cilium as the
> CNI, the k8s version is gated by cilium support → 1.35 is the newest fully-supported target.

> **Apply fix (2026-05-24):** `talos_machine_configuration` never pinned `kubernetes_version`, so the talos 0.11 provider defaulted it to 1.36.0 (rejected by Talos 1.12.8). Pinned both data sources to `var.cilium_config.kube_version` (talos.tf:21,173) — single source of truth for the k8s version.

**Required follow-ups before apply (user):**
- Update the live encrypted `terraform/dev/terraform.tfvars`: `talos.version = "v1.12.8"`,
  `cilium_config.kube_version = "1.35.0"`, `cilium_config.cilium_version = "1.19.4"` (SOPS
  file — not editable here).
- Review k8s 1.33→1.35 workload API compat for the pinned `extra_manifests` (metrics-server
  v0.7.2, gateway-api v1.4.0) and other GitOps controllers. Cluster-wide, beyond the module.
- `terraform plan` and confirm the only diffs are the intended provider/version/`_v1` changes.

## Consequences

**Positive (B)** — `terraform init` works again; one source of truth for machine
config; current providers; latent DNS footgun closed.

**Negative / trade-offs (B)** — kubernetes 3.x deprecation warnings until the root
migrates to `_v1` resources; a 14-version proxmox jump means the first greenfield
apply should be watched closely (VM create path); the apply-time provider-from-output
ordering issue (#15) remains deferred to C.

## Open items (before this becomes Accepted)

**See user answers to open items below**

- Confirm whether dev S3 state was destroyed with the cluster (greenfield assumption);
  if state persists, re-scope the proxmox/kubernetes diffs against it first. **s3 bucket still exists, state does not. close this open item**
- Decide pin style (exact vs `~>`). **Pin exact versions**
- Decide if `aws` is still needed in `terraform/dev` (object-storage/R2 lives in its
  own root) — likely drop the empty block here. **I went ahead and dropped the aws block. Closed**

## Verification (post-implementation)

- `git grep -n 'source *= *"\./talos-pve' terraform/` returns nothing.
- `/lint` clean.
- `/terraform-plan` is clean against empty state.
- (B/C) Spot-check the rendered machine config from the shared template equals the
  prior per-role output before apply.
