# Infrastructure

The platform layers Flux reconciles before any application runs, roughly in
dependency order.

<div class="grid cards" markdown>

-   :material-lan:{ .lg .middle } __[Networking](networking.md)__

    ---

    Cilium Gateway, HTTPRoutes, and external exposure via Tailscale and Cloudflare Tunnel.

-   :material-dns:{ .lg .middle } __[DNS](dns.md)__

    ---

    ExternalDNS and the CoreDNS split-horizon forward for internal `home-0ps.com` names.

-   :material-database:{ .lg .middle } __[Storage](storage.md)__

    ---

    iSCSI CSI, local-path provisioner, and CNPG backups.

-   :material-key-chain:{ .lg .middle } __[Secrets & PKI](secrets-pki.md)__

    ---

    1Password Connect, External Secrets Operator, and the internal CA / trust bundle.

-   :material-chart-line:{ .lg .middle } __[Observability](observability.md)__

    ---

    Prometheus, Grafana, Loki, and the scrape targets.

</div>
