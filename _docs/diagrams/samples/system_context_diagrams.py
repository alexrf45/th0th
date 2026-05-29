"""System-context diagram (mingrammer/diagrams) — vendor-logo style.

Renders a GitOps homelab overview: operator pushes to git, Flux reconciles
layered Kustomizations on Talos/Proxmox, 1Password->Connect->ESO injects
secrets, users reach apps via the Cilium Gateway.
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.gitops import Flux
from diagrams.onprem.vcs import Git
from diagrams.onprem.container import Docker
from diagrams.k8s.infra import Master
from diagrams.k8s.network import Ingress
from diagrams.k8s.compute import Deployment
from diagrams.onprem.security import Vault
from diagrams.generic.os import LinuxGeneral
from diagrams.onprem.client import User, Users

graph_attr = {
    "fontsize": "16",
    "bgcolor": "transparent",
    "pad": "0.4",
    "splines": "spline",
}

with Diagram(
    "GitOps Homelab — System Context",
    filename="/home/fr3d/home-0ps.com/_docs/diagrams/samples/system-context-mingrammer",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    outformat="png",
):
    operator = Users("Operator")
    visitor = User("User")

    repo = Git("Git repo\n(main branch)")

    with Cluster("Secrets pipeline"):
        op = Vault("1Password")
        connect = Docker("1P Connect")
        eso = Vault("External Secrets\nOperator")
        op >> Edge() >> connect >> Edge() >> eso

    with Cluster("Talos Kubernetes on Proxmox"):
        flux = Flux("Flux CD")
        controllers = Master("Controllers")
        gateway = Ingress("Cilium Gateway")
        apps = Deployment("Applications")
        flux >> Edge(label="layered\nKustomizations") >> controllers
        controllers >> Edge() >> gateway
        gateway >> Edge() >> apps

    operator >> Edge(label="git push") >> repo
    repo >> Edge(label="watches & reconciles") >> flux
    eso >> Edge(label="injects Secrets") >> apps
    visitor >> Edge(label="*.lab.example.com") >> gateway
