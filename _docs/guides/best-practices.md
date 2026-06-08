# Best practices & lessons learned

The patterns this lab has settled on, and the hard-won lessons behind them. Read
this before adding an app or changing infra — it's opinionated on purpose, and
the rationale transfers to any Talos + Flux + Cilium + CNPG + External-Secrets
stack.

## 1. GitOps discipline

- **Layer with explicit `dependsOn`.** The Flux DAG is ordered cluster-config →
  crds → controllers → pki → ESO → secrets → networking → dns → storage →
  observability → security → apps. Make each app its **own top-level
  Kustomization** (no shared "applications" bucket) so one app's failure can't
  wedge the others.
- **Operators don't install their own CRDs.** Any operator whose CRs are
  Flux-reconciled sets `crds.enabled: false` (or the chart's equivalent); CRDs
  live in `global/crds/` (the `crds` layer, before controllers), version-pinned
  to the operator chart. This kills the kustomize-controller dry-run race when a
  CR and its CRD-installing chart share a Kustomization. Prefer upstream CRD-only
  subcharts (Renovate updates them for free).
- **Parameterize via `cluster-config`.** Hostnames, versions, and storage params
  live in a `cluster-configs.yaml` ConfigMap and reach manifests through
  `postBuild.substituteFrom`. Watch the **substitution-scope trap**: an HTTPRoute
  in the app layer sees a var that the `networking`-layer cert does not — so cert
  SANs are hardcoded while routes use `${VAR}`.
- **Always go through the `kubeop.sh` wrappers** (`kube`/`k9s-op`/`k8sop`) — the
  kubeconfig is fetched from 1Password on demand, not stored on disk. Raw
  `kubectl`/`flux`/`helm` target nothing. (`talosctl` is the only exception.) See
  [the cluster-access wrapper](../kubectl-wrapper.md).
- **Proxmox RBAC: manage permissions with the dedicated `proxmox_acl` resource,
  not an inline `acl {}` block.** Heads-up that the `bpg/proxmox` provider still
  carries a deprecated computed `acl` block on `proxmox_virtual_environment_user`,
  so `terraform validate/plan` prints an *"Argument is deprecated"* warning for
  **every** user resource — even ones that never set `acl`. It's provider-level
  and benign, not removable from your HCL (slated to drop in bpg `v1.0`). Pair
  each user with a separate `proxmox_virtual_environment_role` + `proxmox_acl` and
  ignore the warning.

## 2. Security & hardening {#2-security--hardening}

### Pod Security Standards
Aim for namespace `pod-security.kubernetes.io/enforce: restricted` with a pod
spec that satisfies it — [Homer](../apps/homer.md#security-posture) is the
simplest worked example. Backfill `restricted` onto every app namespace.

### securityContext — set `runAsUser` explicitly {#kyverno-securitycontext-mutation}
If you run a Kyverno `add-default-securitycontext` policy, it mutates an **unset**
`runAsUser` to `65534`. A pod-level `runAsUser` does **not** override it at the
container level — set `runAsUser` explicitly on **every container**, or the app
runs as the wrong UID and can't read its own files.

### Permissions & writable paths — enumerate them all in one pass {#permissions--writable-paths}
When an image's entrypoint assumes root but you run it unprivileged, do **one**
audit of *every* path it writes (run dirs, log dirs, cache dirs, config, data) —
don't discover them one CrashLoop at a time. The reference implementation is
[FreshRSS](../apps/freshrss.md#the-securitycontext--writable-paths-pattern): a
root init container with only `CHOWN`/`DAC_OVERRIDE`/`FOWNER` seeds config into
`emptyDir`s and pre-`chown`s the data volume, then the main container runs as the
app UID with all caps dropped. Talos `/tmp` is a capped `tmpfs` — use an explicit
`emptyDir` (optionally `medium: Memory` + `sizeLimit`) for scratch.

### Network policies — default-deny per app
Each app ships `*-default-deny` + `*-allow` (+ `*-cnpg-allow` if it has a DB).
Two non-obvious rules:
- **Gateway backends need `fromEntities: [ingress]`** — Cilium Gateway
  proxy→backend traffic carries the `reserved:ingress` identity; `host`/
  `remote-node` only covers kubelet probes.
- **CNPG instances need operator ingress on 8000** — every `*-cnpg-allow` must
  allow the `cloudnative-pg` operator (database ns) or fresh clusters hang at
  `1/N`.

### Log shippers run as root {#log-shippers-need-root}
`capabilities.add` lands in the *bounding* set only on non-root pods, so
Alloy/Promtail-style shippers need `runAsUser: 0` to read `/var/log/pods`.
Counter-intuitive, but required.

## 3. Resilience

Apply these to every stateful app, in priority order:

1. **PodDisruptionBudget + `terminationGracePeriodSeconds`.** A node drain (e.g.
   a Talos upgrade) will evict a DB-backed pod with no in-flight protection
   otherwise. Add a `policy/v1 PodDisruptionBudget` (`maxUnavailable: 1`) per app;
   let CNPG manage its own DB-pod disruption with its primitives rather than a
   hand-rolled PDB over CNPG pods. Bump grace to 30–120s so in-flight requests
   finish.
2. **ResourceQuota + LimitRange per app namespace.** Bound everything — one
   runaway pod can starve the cluster. Put them in `base/` (LimitRange defaults
   apply at admission); seed values from `kube dev top pod -n <ns>` once
   Prometheus has history. Start loose, tighten with ~30 days of data.
3. **Probe audit.** Liveness + readiness on every app; liveness on a longer
   `initialDelaySeconds`. Don't reuse `pg_isready` as an app dependency probe — it
   doesn't check replication/WAL; let CNPG status drive that. A `startupProbe` is
   overkill for anything that comes up in <30s.
4. **HA is a deliberate trade, not a default.** Single-instance CNPG is the right
   call for a single-operator lab — a 3-node quorum doesn't survive the real
   failure domains (NAS, rack, house). Put durability in ZFS (RAID + snapshots)
   and accept minutes of downtime on reschedule. Don't add an HPA to a stateful
   single-instance app.

## 4. Secrets

- **Keep everything rotatable.** Never move a 1Password-backed `ExternalSecret`
  field to a literal, even if it's non-sensitive — rotation flexibility is the
  point.
- **One 1P item → one ExternalSecret → one Secret**, even when it emits multiple
  key shapes (CNPG ignores extra keys). See
  [Secrets & PKI](../infra/secrets-pki.md).
- **Generate plaintext drafts; encrypt deliberately.** Treat SOPS/`.env` files as
  operator-owned — don't re-encrypt them casually.
- Rotated 1P values only matter for the *next* pod start; force a resync with the
  `force-sync` annotation when you need it immediately.

## 5. Storage & data

- **Durability belongs in the storage layer, not the app replica count.** ZFS
  RAID + snapshots beat N ephemeral local-path copies.
- **Static volumes over dynamic for anything you want to keep.** Pre-create the
  zvol, check a `Retain` PV+PVC into the overlay, pin with `volumeName` (the
  [static-volume pattern](../infra/storage.md#provision-a-static-iscsi-volume)).
  Set the dynamic `iscsi` class to `Retain` too.
- **CNPG bootstrap is one-shot/immutable.** To retry recovery: suspend Flux,
  delete the `Cluster` + instance PVCs, resume. CNPG doesn't GC instance PVCs on
  cluster deletion — that's what enables the soft-teardown / re-adopt loop.
  **Never** point `bootstrap.initdb` at a zvol that already holds PGDATA.

## 6. Observability — highest-ROI moves

- **Kubernetes Warning events → Loki is the single best low-effort add.** Add
  `loki.source.kubernetes_events` to Alloy — but verify the Alloy ServiceAccount
  has `events {get,list,watch}` first (ship the RBAC in the same commit).
- **Offload logs off-cluster** so retention outlives the cluster (Loki on a
  small bare-metal host over Tailscale).
- **Periodic posture scans** (`popeye`, `kubescape`) as low-priority CronJobs →
  Loki are a forcing function for the resilience items above.

## 7. Operations & DR

- **Write the recovery runbook when you build the thing, not after the outage.**
  Authentik's break-glass admin + the CNPG-restore steps existed before they were
  needed ([Authentik](../apps/authentik.md#recovery-and-day-2),
  [Database rescue](cnpg-rescue.md)).
- **Debugging discipline:** state the exact symptom, read the failing
  component's real config/logs, form a hypothesis with a verification step,
  *then* fix. Don't stack speculative fixes.
- **Document manual one-offs too** — e.g. set mini-PC BIOS "AC Power Loss → Power
  On" (pairs with Proxmox HA for power-blip self-recovery), and verify it on
  every node.

## 8. Things to skip on a Talos lab {#things-to-skip-on-a-talos-lab}

Advice aimed at single-server `k3s`/`nginx`/`ufw` setups doesn't apply here:

- **Single-node `k3s`** — a multi-node Talos cluster exists *specifically* to
  learn HA primitives. Don't downscale.
- **Ansible / bash config management** — GitOps (Terraform + Flux + Renovate)
  replaces it; adopting Ansible would be a regression.
- **ufw + fail2ban** — Talos is a read-only OS with no SSH and a restricted kube
  API; its threat model is already stricter.
- **An LLM with cluster write access** — never connect one to a live cluster;
  read-only through a scoped ServiceAccount only.
