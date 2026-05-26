output "tunnel_id" {
  description = "Cloudflare tunnel UUID."
  value       = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "tunnel_cname_target" {
  description = "CNAME target for public hostnames routed through this tunnel (used in G2: status.home-0ps.com -> this)."
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
}
