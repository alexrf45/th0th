<div align="center">

<img src="https://avatars.githubusercontent.com/u/61287648?s=200&v=4" align="center" width="144px" height="144px" alt="kubernetes"/>

<a href="https://dev-status.home-0ps.com"><img src="https://img.shields.io/badge/home--0ps.com-blue?style=plastic" alt="home-0ps.com" height="140px" width="140px"/></a>

**_A living, breathing home lab that champions a love of learning and discovery_**

</div>

<div align="center">

## Live status

### Cluster

![Talos](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-kromgo.home-0ps.com%2Ftalos_version&style=plastic&logo=Talos&logoColor=%23FF7300)
![Kubernetes](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-kromgo.home-0ps.com%2Fkubernetes_version&style=plastic&logo=Kubernetes&logoColor=%23326CE5&logoSize=auto)
![Flux](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-kromgo.home-0ps.com%2Fflux_version&style=plastic&logo=flux&logoSize=auto)
![Nodes](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-kromgo.home-0ps.com%2Fcluster_node_count&style=plastic&logo=Kubernetes&logoColor=%23326CE5&logoSize=auto)
![Pods](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-kromgo.home-0ps.com%2Fcluster_pod_count&style=plastic&logo=Kubernetes&logoColor=%23326CE5&logoSize=auto)
![Age](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-kromgo.home-0ps.com%2Fcluster_age_days&style=plastic&logo=prometheus&logoColor=%23E6522C)
![Uptime](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-kromgo.home-0ps.com%2Fcluster_uptime_days&style=plastic&logo=prometheus&logoColor=%23E6522C)
![CPU](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-kromgo.home-0ps.com%2Fcluster_cpu_usage&style=plastic&logo=prometheus&logoColor=%23E6522C)
![Memory](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-kromgo.home-0ps.com%2Fcluster_memory_usage&style=plastic&logo=prometheus&logoColor=%23E6522C)
![Alerts](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-kromgo.home-0ps.com%2Fcluster_alert_count&style=plastic&logo=prometheus&logoColor=%23E6522C)

### Applications

| Application                                                                                | Status                                                                                                                                                        | Uptime (7d)                                                                                             | Purpose                |
| ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ---------------------- |
| ![Authentik](https://img.shields.io/badge/Authentik-FD4B2D?logo=authentik&logoColor=white) | ![status](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-status.home-0ps.com%2Fapi%2Fv1%2Fendpoints%2Fapplications_authentik%2Fhealth%2Fbadge.shields) | ![uptime](https://dev-status.home-0ps.com/api/v1/endpoints/applications_authentik/uptimes/7d/badge.svg) | SSO / IdP              |
| ![Grafana](https://img.shields.io/badge/Grafana-F46800?logo=grafana&logoColor=white)       | ![status](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-status.home-0ps.com%2Fapi%2Fv1%2Fendpoints%2Fapplications_grafana%2Fhealth%2Fbadge.shields)   | ![uptime](https://dev-status.home-0ps.com/api/v1/endpoints/applications_grafana/uptimes/7d/badge.svg)   | Observability UI       |
| ![FreshRSS](https://img.shields.io/badge/FreshRSS-2D2D2D?logo=rss&logoColor=white)         | ![status](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-status.home-0ps.com%2Fapi%2Fv1%2Fendpoints%2Fapplications_freshrss%2Fhealth%2Fbadge.shields)  | ![uptime](https://dev-status.home-0ps.com/api/v1/endpoints/applications_freshrss/uptimes/7d/badge.svg)  | Self-hosted RSS reader |
| ![Homer](https://img.shields.io/badge/Homer-2D2D2D?logo=homeassistant&logoColor=white)     | ![status](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-status.home-0ps.com%2Fapi%2Fv1%2Fendpoints%2Fapplications_homer%2Fhealth%2Fbadge.shields)     | ![uptime](https://dev-status.home-0ps.com/api/v1/endpoints/applications_homer/uptimes/7d/badge.svg)     | Service dashboard      |

### Infrastructure

| Target                                                                               | Status                                                                                                                                                        | Uptime (7d)                                                                                             | Purpose                     |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- | --------------------------- |
| ![TrueNAS](https://img.shields.io/badge/TrueNAS-0095D5?logo=truenas&logoColor=white) | ![status](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-status.home-0ps.com%2Fapi%2Fv1%2Fendpoints%2Finfrastructure_truenas%2Fhealth%2Fbadge.shields) | ![uptime](https://dev-status.home-0ps.com/api/v1/endpoints/infrastructure_truenas/uptimes/7d/badge.svg) | iSCSI / NFS storage backend |
| ![UniFi](https://img.shields.io/badge/UniFi-0559C9?logo=ubiquiti&logoColor=white)    | ![status](https://img.shields.io/endpoint?url=https%3A%2F%2Fdev-status.home-0ps.com%2Fapi%2Fv1%2Fendpoints%2Finfrastructure_unifi%2Fhealth%2Fbadge.shields)   | ![uptime](https://dev-status.home-0ps.com/api/v1/endpoints/infrastructure_unifi/uptimes/7d/badge.svg)   | Edge gateway / DNS resolver |

</div>

<div align="center">

## Architecture

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Proxmox](https://img.shields.io/badge/Proxmox-E57000?logo=proxmox&logoColor=white)
![Flux](https://img.shields.io/badge/Flux-5468FF?logo=flux&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-0F1689?logo=helm&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?logo=kubernetes&logoColor=white)
![Cilium](https://img.shields.io/badge/Cilium-F8C517?logo=cilium&logoColor=black)
![CoreDNS](https://img.shields.io/badge/CoreDNS-1F7DD1?logo=coredns&logoColor=white)
![ExternalDNS](https://img.shields.io/badge/External_DNS-326CE5?logo=kubernetes&logoColor=white)
![Ubiquiti](https://img.shields.io/badge/Ubiquiti-0559C9?logo=ubiquiti&logoColor=white)
![Storage](https://img.shields.io/badge/Local_Path-326CE5?logo=kubernetes&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)
![CloudNativePG](https://img.shields.io/badge/CloudNativePG-336791?logo=postgresql&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-F46800?logo=grafana&logoColor=white)
![Loki](https://img.shields.io/badge/Loki-F46800?logo=grafana&logoColor=white)
![Alloy](https://img.shields.io/badge/Grafana_Alloy-F46800?logo=grafana&logoColor=white)
![Gatus](https://img.shields.io/badge/Gatus-2D2D2D?logo=statuspage&logoColor=white)
![Cert-Manager](https://img.shields.io/badge/cert--manager-326CE5?logo=kubernetes&logoColor=white)
![External Secrets](https://img.shields.io/badge/External_Secrets-326CE5?logo=kubernetes&logoColor=white)
![1Password](https://img.shields.io/badge/1Password-0094F5?logo=1password&logoColor=white)
![SOPS](https://img.shields.io/badge/SOPS-1A1A1A?logo=mozilla&logoColor=white)
![Renovate](https://img.shields.io/badge/Renovate-1A1F6C?logo=renovatebot&logoColor=white)
![Authentik](https://img.shields.io/badge/Authentik-FD4B2D?logo=authentik&logoColor=white)
![Kyverno](https://img.shields.io/badge/Kyverno-3BCEAC?logo=kubernetes&logoColor=white)
![Falco](https://img.shields.io/badge/Falco-00AEEF?logo=falco&logoColor=white)
![Trivy](https://img.shields.io/badge/Trivy-1904DA?logo=aquasecurity&logoColor=white)
![Tailscale](https://img.shields.io/badge/Tailscale-242424?logo=tailscale&logoColor=white)
![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?logo=cloudflare&logoColor=white)

</div>
