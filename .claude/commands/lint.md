Lint the Infrastructure as Code: `terraform fmt`/`validate` and `packer fmt`/`validate` across `_infra/`.

Read-only — never runs plan/apply or touches state. Uses the raw terraform/packer binaries (bypasses the 1Password wrapper, which is only needed for plan/apply).

```bash
bash _hack/scripts/iac-lint.sh
```

Report the result. On a `fmt` failure, tell the user the exact `terraform fmt -recursive _infra/terraform` / `packer fmt -recursive _infra/packer` command to fix it. On a `validate` failure, surface the offending directory and error. Directories whose `init` failed offline (no provider/plugin network) are skipped, not failed — note them if any.
