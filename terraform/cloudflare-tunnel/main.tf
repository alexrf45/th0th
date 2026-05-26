# Remotely-managed (token-based) tunnel. cloudflared in-cluster runs with only
# the connector token (TUNNEL_TOKEN); ingress/public-hostname config is managed
# on the Cloudflare side — added in G2 via cloudflare_zero_trust_tunnel_cloudflared_config
# + a DNS record, once Gatus exists.
resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  config_src = "cloudflare"
}

# The connector token for the tunnel (v5: exposed via a data source, not the
# resource). Stable for a given tunnel, so no perpetual diff.
data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

# Publish the token to 1Password so the cluster ExternalSecret
# (_lib/networking/cloudflared/externalsecret.yaml → key cf_tunnel_home-0ps.com,
# property tunnel-token) ingests it. Rotatable: re-apply republishes; ESO
# re-syncs within its refreshInterval.
resource "onepassword_item" "cf_tunnel" {
  vault    = var.op_vault_id
  title    = "cf_tunnel_home-0ps.com"
  category = "password"

  section {
    label = "tunnel"

    field {
      label = "tunnel-token"
      type  = "CONCEALED"
      value = data.cloudflare_zero_trust_tunnel_cloudflared_token.this.token
    }
  }
}
