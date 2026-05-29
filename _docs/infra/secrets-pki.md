# Secrets & PKI

Two trust roots underpin the lab: **1Password** (secret material, via External
Secrets) and an **internal CA** (service-to-service TLS). The guiding principle:
keep secrets **rotatable** — never hardcode a 1Password-backed field, even a
non-sensitive one, because rotation flexibility is the goal.

**Layers:** `external-secrets-operator` + `secrets` (runtime secrets); `pki`
(internal CA / trust).

## Secret flow

```
1Password  →  1Password Connect  →  External Secrets Operator  →  Kubernetes Secret  →  workload
  (vault)      (in-cluster API)        (ExternalSecret CR)           (synced)
```

| Component | Path | Notes |
| --- | --- | --- |
| 1Password Connect | `_lib/secrets/onepassword/` | chart `connect@2.0.5`, `onepassword` ns; `op-connect-tls` cert; scraped by Prometheus |
| External Secrets Operator | `_lib/controllers/external-secrets/` | chart `0.20.1`; its Flux layer `dependsOn` controllers **+ pki** (for mTLS) |
| ClusterSecretStore | `_lib/secrets/cluster-secret-store/` | the cluster-wide store apps reference |

Each app declares an `ExternalSecret` referencing a 1Password item; ESO produces
the Kubernetes Secret. Convention: **one 1Password item → one `ExternalSecret` →
one Secret**, even when that Secret emits multiple key shapes (see the Authentik
DB+chart secret in [Authentik](../apps/authentik.md#secrets)).

Not on 1Password? ESO supports many backends (Vault, AWS/GCP secret managers,
Kubernetes) — only the `ClusterSecretStore` provider block changes.

## SOPS (Flux-decrypted secrets)

For secrets that must live in git (object-storage creds, the Cloudflare DNS
token, Tailscale keys), Flux decrypts at reconcile time with a `sops-age` secret
in `flux-system`. The SOPS config (`.sops.yaml`) controls scope:

- files matching `*values.yaml` are **fully** encrypted;
- other YAML encrypts only `data`/`stringData` (or a per-file `encrypted-regex`).

> **Discipline:** treat SOPS/`.env` files as operator-owned — generate plaintext
> drafts (`*.plain.yaml`) and encrypt them deliberately; don't re-encrypt
> existing secret files casually. The Age key is seeded from your secret manager
> at bootstrap (Terraform `kubernetes_secret`).

## Internal PKI

`_lib/pki/` provides service-to-service TLS independent of Let's Encrypt:

| Path | What |
| --- | --- |
| `certauth/…-ca-keypair.yaml` | internal CA keypair (SOPS) |
| `certauth/int-cluster-issuer.yaml` | cert-manager Issuer backed by the CA |
| `trust-manager/` | trust-manager `v0.16.0` |
| `trust-bundle/bundle.yaml` | distributes the CA bundle to namespaces |

Internal certs (trust-manager, 1P Connect, and any service-to-service mTLS) are
issued from this CA. The `pki` layer is a dependency of ESO so 1P Connect's mTLS
is available before secrets sync.

## CNPG network-policy dependency (easy to miss)

Every new `<app>-cnpg-allow` network policy must allow ingress from the CNPG
operator (the database namespace + `cloudnative-pg` label) on **port 8000** —
otherwise fresh database clusters get stuck at `1/N` instances.

## Rotation notes

- **1Password-backed fields** resync on the `ExternalSecret` `refreshInterval`
  (typically 5–15m). Running pods don't re-read — rotation takes effect on the
  *next* restart. Force a sync with
  `kube dev -n <ns> annotate externalsecret <name> force-sync="$(date +%s)" --overwrite`.
- **Object-storage / Cloudflare tokens** are Terraform-managed (90–180-day TTL);
  re-issue via a targeted `terraform apply` and ESO picks up the rewritten item.
