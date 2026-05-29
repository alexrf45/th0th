# Cluster access (`kubeop.sh`)

The kubeconfig for every cluster in this lab lives in 1Password (written there
by the Talos Terraform module as a Secure Note titled
`<cluster-name>-kubeconfig`). It never lands on disk.

To make this ergonomic, a small zsh helper at [`_hack/scripts/kubeop.sh`](./_hack/scripts/kubeop.sh)
(also kept in `~/.zsh/kubeop.sh` on the operator workstation) fetches the
kubeconfig on demand via `op read` and feeds it to kubeconfig-aware tools via
process substitution — the config materializes as a `/dev/fd/N` pipe inside a
short-lived bash subshell and is never written to a file.

Source it from your `~/.zshrc`:

```bash
source ~/.zsh/kubeop.sh
```

It exposes four functions:

| Function                    | Purpose                                                                                |
| --------------------------- | -------------------------------------------------------------------------------------- |
| `kube [env] <args>`         | kubectl (env defaults to `dev`)                                                        |
| `k9s-op [env] <args>`       | k9s                                                                                    |
| `k8sop <env> <tool> <args>` | any kubeconfig-aware tool: flux, helm, kustomize, kubectl-cnpg, stern, kubecolor, etc. |
| `kube-flush`                | drop the in-memory kubeconfig cache and force a re-fetch                               |

Examples:

```bash
kube dev get pods -A
kube dev -n freshrss rollout restart deploy/freshrss
k8sop dev flux reconcile kustomization security
k8sop dev helm list -A
k8sop dev kustomize build _lib/applications/freshrss/overlays/dev
k8sop dev stern -n freshrss .
```

**Why use this pattern in your own lab:**

- **Zero plaintext kubeconfigs at rest.** Compromise of a workstation user
  account doesn't immediately leak cluster admin creds; the secret is only
  ever in environment-variable / file-descriptor form during a single command.
- **Single source of truth.** Cluster bootstrap (Terraform) writes the
  credential; everyone who needs it pulls it the same way. No `scp`-ing
  configs, no stale `~/.kube/config` merges.
- **Multi-cluster from one shell.** `dev`, `staging`, `prod` are positional
  args — no `kubectx` dance, no risk of acting on the wrong cluster because
  you forgot to switch context.
- **Works with anything that takes `--kubeconfig`.** kubectl, k9s, flux, helm,
  kustomize, stern, kubectl-cnpg, kubecolor — all transparent.

Prerequisites: 1Password CLI (`op`) signed in, `bash` available at `/bin/bash`,
and the cluster's kubeconfig stored in the configured vault as a Secure Note
named `<cluster-name>-kubeconfig`. Override the vault per-shell with
`export OP_VAULT="..."` before sourcing the script.

Caveat: the wrapper hardcodes `--kubeconfig`, so it won't work for tools that
use a different flag (notably `talosctl`, which uses `--talosconfig`). Run
those directly.
