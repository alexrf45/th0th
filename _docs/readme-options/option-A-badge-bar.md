<!-- ============================================================
     OPTION A — Banner-led header with a "for-the-badge" pill bar.
     The pills act as a header strip and restore the what-is-this /
     how-far-along signal. Drop the `# th0th` H1 if your banner art
     already contains the wordmark.
     ============================================================ -->

<div align="center">

<img src="https://github.com/user-attachments/assets/66fcda90-452a-4ebe-996f-4ac9aff82281" alt="th0th" width="880" />

**_A reproducible security research lab — offense, defense, and everything between, fully isolated._**

[![th0th.dev](https://img.shields.io/badge/th0th.dev-1A1A1A?style=for-the-badge&logo=cloudflare&logoColor=white)](https://th0th.dev)
&nbsp;![cyber range](https://img.shields.io/badge/cyber-range-C9252A?style=for-the-badge)
&nbsp;![build](https://img.shields.io/badge/build-phase_2-2EA44F?style=for-the-badge)

</div>

---

`th0th` is a self-hosted **cyber range** built as Infrastructure as Code on a 6-node
Proxmox cluster. It exists to practice offensive **and** defensive techniques, develop
bespoke tooling and detections for Linux and Windows, and to study CVEs & malware —
inside networks isolated at the hypervisor, so nothing detonated can reach the home or
management network.

<div align="center">

![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)
![Packer](https://img.shields.io/badge/Packer-02A8EF?logo=packer&logoColor=white)
![Proxmox](https://img.shields.io/badge/Proxmox-E57000?logo=proxmox&logoColor=white)
![Kali Linux](https://img.shields.io/badge/Kali-557C94?logo=kalilinux&logoColor=white)
![Windows AD](https://img.shields.io/badge/Windows_AD-0078D6?logo=windows&logoColor=white)
![Sysmon](https://img.shields.io/badge/Sysmon-2D2D2D?logo=windows&logoColor=white)
![Wazuh](https://img.shields.io/badge/Wazuh-3781C2?logo=wazuh&logoColor=white)
![MITRE ATT&CK](https://img.shields.io/badge/ATT%26CK-C9252A?logo=mitre&logoColor=white)
![1Password](https://img.shields.io/badge/1Password-0094F5?logo=1password&logoColor=white)
![SOPS](https://img.shields.io/badge/SOPS-1A1A1A?logo=mozilla&logoColor=white)

## Build status

| Phase | Scope | In repo | Deployed |
| ----- | ----- | :-----: | :------: |
| **0 · Segmentation** | VLAN-zone range; gateway-less, air-gapped detonation nets | ✅ | ⬜ |
| **1 · Golden images** | Packer templates — Ubuntu, Kali, Windows Server / 10 / 11 | ✅ | ⬜ |
| **2 · AD detection lab** | DC + workstations + Kali; planted Kerberoast / AS-REP / ACL misconfigs | ✅ | ⬜ |
| **3 · Defensive (Wazuh)** | one-way detonation → collector telemetry, detection engineering | 🔜 | ⬜ |
| **4 · Offensive + C2** | payload / tool development, delivery, callbacks | ⬜ | ⬜ |
| **5 · Web / CVE workbench** | disposable vulnerable apps, snapshot / rollback | ⬜ | ⬜ |

## Capabilities

| Domain | In the range |
| ------ | ------------ |
| 🔴 **Offensive** | A Kali attacker box, payload & tool development, and C2 — delivered into isolated networks. |
| 🔵 **Defensive** | Detection engineering: Sysmon + auditd shipped one-way (threat/payload → collector) into Wazuh. |
| 🐛 **CVE testing** | Ephemeral victims with `clean-baseline` snapshots — repeatable, rollback-friendly. |

</div>

## Safety & scope

> Authorized, personal, and isolated. Detonation networks have **no gateway** — no route
> to the home / management LAN, TrueNAS, the internet, or each other, even if a victim is
> fully compromised. Scenario disks stay **node-local**; nothing vulnerable touches the
> NAS. Invariants: [`.claude/rules/lab-isolation.md`](../../.claude/rules/lab-isolation.md).

## Getting started

- **[Bring-up runbook](../runbooks/security-lab-bring-up.md)** — the ordered Phase 0 → 2 build with verification gates.
- **[ADR-0009](../decisions/0009-security-lab-segmentation.md)** — the segmentation design and why VLAN zones (not EVPN).
- **[`.claude/rules/lab-isolation.md`](../../.claude/rules/lab-isolation.md)** — the safety invariants to read before touching the range.
