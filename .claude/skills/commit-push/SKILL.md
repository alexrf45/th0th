# Commit and Push
Stage changes, write a conventional commit message based on the diff,
commit with 1Password SSH signing, push, and run `flux reconcile kustomization
flux-system --with-source` if k8s manifests changed. Verify reconcile success.
