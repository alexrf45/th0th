<div align="center">

<!-- TODO: swap this k8s avatar for a range emblem (Thoth / ibis / sigil motif) -->
<img src="https://avatars.githubusercontent.com/u/61287648?s=200&v=4" width="144px" height="144px" alt="th0th"/>

<br/>
<br/>

<a href="https://th0th.dev"><img src="https://img.shields.io/badge/th0th.dev-1A1A1A?style=plastic" alt="th0th.dev" height="28px" /></a>

**_A reproducible security research lab: offense, defense, and everything between — fully isolated._**

</div>

---

`th0th` is a self-hosted **cyber range** built as Infrastructure as Code on a 6-node
Proxmox cluster. It exists to practice offensive **and** defensive technique, to
develop bespoke tooling and detections for Linux and Windows, and to study CVEs —
inside network segments isolated at the hypervisor, so a detonated payload can never
reach the home or management network.

<div align="center">

## Build status

| Phase | Scope | In repo | Deployed |
| ----- | ----- | :-----: | :------: |
| **0 · Segmentation** | VLAN-zone range; gateway-less, air-gapped detonation nets | ✅ | ⬜ |
| **1 · Golden images** | Packer templates — Ubuntu, Kali, Windows Server / 10 / 11 | ✅ | ⬜ |
| **2 · AD detection lab** | DC + workstations + Kali; planted Kerberoast / AS-REP / ACL misconfigs | ✅ | ⬜ |
| **3 · Defensive (Wazuh)** | one-way detonation → collector telemetry, detection engineering | 🔜 | ⬜ |
| **4 · Offensive + C2** | payload / tool development, delivery, callbacks | ⬜ | ⬜ |
| **5 · Web / CVE workbench** | disposable vulnerable apps, snapshot / rollback | ⬜ | ⬜ |

</div>

## Capabilities

| Domain | In the range |
| ------ | ------------ |
| 🔴 **Offensive** | A Kali attacker box, payload & tool development, and C2 — delivered into isolated detonation networks. |
| 🔵 **Defensive** | Detection engineering: Sysmon + auditd shipped one-way (detonation → collector) into Wazuh. |
| 🐛 **CVE testing** | Ephemeral victims with `clean-baseline` snapshots for repeatable, rollback-friendly detonation. |

<div align="center">

## Architecture

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Packer](https://img.shields.io/badge/Packer-02A8EF?logo=packer&logoColor=white)
![Proxmox](https://img.shields.io/badge/Proxmox-E57000?logo=proxmox&logoColor=white)
![UniFi](https://img.shields.io/badge/UniFi-0559C9?logo=ubiquiti&logoColor=white)
![TrueNAS](https://img.shields.io/badge/TrueNAS-0095D5?logo=truenas&logoColor=white)
![1Password](https://img.shields.io/badge/1Password-0094F5?logo=1password&logoColor=white)
![SOPS](https://img.shields.io/badge/SOPS-1A1A1A?logo=mozilla&logoColor=white)
![Kali Linux](https://img.shields.io/badge/Kali_Linux-557C94?logo=kalilinux&logoColor=white)
![Windows AD](https://img.shields.io/badge/Windows_AD-0078D6?logo=windows&logoColor=white)
![Sysmon](https://img.shields.io/badge/Sysmon-2D2D2D?logo=windows&logoColor=white)
![Wazuh](https://img.shields.io/badge/Wazuh-3781C2?logo=wazuh&logoColor=white)
![MITRE ATT&CK](https://img.shields.io/badge/MITRE_ATT%26CK-C9252A?logo=mitre&logoColor=white)

</div>

Segmentation is enforced with **Proxmox SDN VLAN zones** backed by the UniFi switch:
detonation VLANs are **gateway-less L2 islands**, so a fully-compromised victim has
no L3 next-hop off its segment. The only bridges in are deliberately dual-homed ops
boxes (Kali, the collector). Provisioned with **Terraform** + **Packer** under
[`_infra/`](_infra/); secrets via **1Password** + **SOPS**.

## Safety & scope

> Authorized, personal, and isolated. Detonation networks have **no gateway** — no
> route to the home / management LAN, TrueNAS, the internet, or each other, even if a
> victim is fully compromised. Scenario disks stay **node-local**; nothing vulnerable
> ever touches the NAS. The non-negotiable invariants live in
> [`.claude/rules/lab-isolation.md`](.claude/rules/lab-isolation.md).

## Getting started

- **[Bring-up runbook](_docs/runbooks/security-lab-bring-up.md)** — the ordered Phase 0 → 2 build with verification gates.
- **[ADR-0009](_docs/decisions/0009-security-lab-segmentation.md)** — the segmentation design and why VLAN zones (not EVPN).
- **[`.claude/rules/lab-isolation.md`](.claude/rules/lab-isolation.md)** — the safety invariants to read before touching the range.
