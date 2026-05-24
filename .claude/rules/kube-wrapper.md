## Kubernetes Operations

- Always use the `k8sop` (or `kube`) wrapper for kubectl commands, not raw `kubectl`
- Verify operator/wrapper conventions before executing cluster commands

The kubeconfig is **not on disk**. It lives in 1Password and is fetched on demand
by `~/.zsh/kubeop.sh`, which is sourced from `~/.zshrc`. Every command that
talks to a live cluster MUST go through one of these wrappers:

| Wrapper                     | Use for                                                                                      |
| --------------------------- | -------------------------------------------------------------------------------------------- |
| `kube [env] <args>`         | kubectl (env defaults to `dev`)                                                              |
| `k9s-op [env] <args>`       | k9s                                                                                          |
| `k8sop <env> <tool> <args>` | any other kubeconfig-aware tool: flux, helm, kustomize, kubectl-cnpg, stern, kubecolor, etc. |
| `kube-flush`                | drop the cached kubeconfig (re-fetch on next call)                                           |

Examples:

- `kube dev get pods -A`
- `kube dev -n freshrss rollout restart deploy/freshrss`
- `k8sop dev flux reconcile kustomization security --with-source`
- `k8sop dev helm list -A`
- `k8sop dev kustomize build _lib/applications/wallabag/overlays/dev`

**Never** invoke raw `kubectl …`, `flux …`, `helm …`, or `kustomize build …`
against the cluster — those have no kubeconfig and will fail or target the
wrong context. This applies to slash commands, verification steps, runbooks,
and follow-up suggestions.

**Exception — talosctl:** the wrapper injects `--kubeconfig`, which talosctl
does not accept. `talosctl …` calls use a separate `--talosconfig` flow that
the user manages outside this wrapper, so leave them un-wrapped.

**Common mistake:** `kube dev kubectl get nodes` — `kube` already implies
`kubectl`. The duplicated tool name turns into a kubectl plugin lookup. Use
`kube dev get nodes` or the explicit `k8sop dev kubectl get nodes`.

Env → cluster mapping (from `_kubeop_cluster_for_env` in the wrapper):
`dev → memphis`, `staging → staging`, `prod → prod`. The 1Password Secure
Note is titled `<cluster-name>-kubeconfig` and is exported by the terraform
module at `terraform/dev/talos-pve-v3.1.0/config-export.tf`.
