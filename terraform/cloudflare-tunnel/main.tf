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

# G2 — public ingress for the Gatus status page. Remotely-managed config is
# pushed to Cloudflare; the cluster cloudflared connectors pick it up
# automatically (no redeploy). Routes dev-status.home-0ps.com to the in-cluster
# gatus service. Add more public hostnames by appending to the ingress list
# (the trailing http_status:404 catch-all stays last).
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.this.id

  config = {
    ingress = [
      {
        hostname = "dev-status.home-0ps.com"
        service  = "http://gatus.gatus.svc.cluster.local:8080"
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

# CNAME -> tunnel; orange-cloud (proxied) so the tunnel actually routes it.
resource "cloudflare_dns_record" "gatus_public" {
  zone_id = var.cloudflare_zone_id
  name    = "dev-status.home-0ps.com"
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  ttl     = 1 # 1 = automatic; required when proxied
  proxied = true
  comment = "Gatus public status page (managed by terraform/cloudflare-tunnel)"
}
