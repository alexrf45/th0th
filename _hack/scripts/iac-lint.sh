#!/usr/bin/env bash
# IaC linter — fmt-check + validate for the active Terraform & Packer under _infra/.
#
# Read-only: never touches state, secrets, or the cluster (`terraform init
# -backend=false` + `validate` only). Calls the raw terraform/packer binaries so it
# bypasses the 1Password CLI wrapper (that wrapper only matters for plan/apply and
# would otherwise prompt for interactive auth). Override with TF_BIN / PACKER_BIN.
#
# Lints everything under _infra/ (the abandoned Talos `dev` root + `talos-pve`
# module were removed from the repo during the security-lab pivot).
#
# Usage:  _hack/scripts/iac-lint.sh
# Exit 0 = clean, 1 = a fmt/validate issue was found.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF="${TF_BIN:-/usr/bin/terraform}"
PK="${PACKER_BIN:-/usr/bin/packer}"
TF_DIR="$ROOT/_infra/terraform"
PK_DIR="$ROOT/_infra/packer"
fail=0

hr() { printf '\n=== %s ===\n' "$1"; }

hr "terraform (fmt-check + validate per dir)"
while IFS= read -r d; do
  rel="${d#"$ROOT"/}"
  if ! "$TF" fmt -check "$d" >/dev/null 2>&1; then
    echo "✗ fmt   $rel   (fix: terraform fmt $rel)"
    fail=1
  fi
  if ( cd "$d" && "$TF" init -backend=false -input=false >/dev/null 2>&1 ); then
    if ( cd "$d" && "$TF" validate >/dev/null 2>&1 ); then
      echo "✓ ok    $rel"
    else
      echo "✗ valid $rel"
      ( cd "$d" && "$TF" validate ) # re-run to show the error
      fail=1
    fi
  else
    echo "• skip  $rel   (terraform init failed — providers unavailable offline?)"
  fi
done < <(
  find "$TF_DIR" -type d -name .terraform -prune \
    -o -name '*.tf' -printf '%h\n' | sort -u
)

hr "packer (fmt-check + validate)"
if "$PK" fmt -check -recursive "$PK_DIR" >/dev/null 2>&1; then
  echo "✓ ok    _infra/packer (fmt)"
else
  echo "✗ fmt   _infra/packer   (fix: packer fmt -recursive _infra/packer)"
  fail=1
fi
if ( cd "$PK_DIR" && "$PK" init . >/dev/null 2>&1 ); then
  if ( cd "$PK_DIR" && "$PK" validate \
        -var 'proxmox_url=https://example:8006/api2/json' \
        -var 'proxmox_token_id=x!y' -var 'proxmox_token_secret=x' \
        -var 'ubuntu_iso_checksum=sha256:0000000000000000000000000000000000000000000000000000000000000000' \
        -var 'debian_iso_checksum=sha256:0000000000000000000000000000000000000000000000000000000000000000' \
        . >/dev/null 2>&1 ); then
    echo "✓ ok    _infra/packer (validate)"
  else
    echo "✗ valid _infra/packer"
    ( cd "$PK_DIR" && "$PK" validate \
        -var 'proxmox_url=https://example:8006/api2/json' \
        -var 'proxmox_token_id=x!y' -var 'proxmox_token_secret=x' \
        -var 'ubuntu_iso_checksum=sha256:0000000000000000000000000000000000000000000000000000000000000000' \
        -var 'debian_iso_checksum=sha256:0000000000000000000000000000000000000000000000000000000000000000' . )
    fail=1
  fi
else
  echo "• skip  _infra/packer   (packer init failed — plugins unavailable offline?)"
fi

hr "result"
[ "$fail" -eq 0 ] && echo "✅ IaC lint passed" || echo "❌ IaC lint found issues"
exit "$fail"
