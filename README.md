<div align="center">

# Th0th

<img width="1600" height="896" alt="thothv1" src="https://github.com/user-attachments/assets/66fcda90-452a-4ebe-996f-4ac9aff82281" />


<a href="https://th0th.dev"><img src="https://img.shields.io/badge/th0th.dev-1A1A1A?style=plastic" alt="th0th.dev" height="100px" /></a>

**_A reproducible security research lab: offense, defense, and everything between — fully isolated._**

</div>

---

`th0th` is a self-hosted **cyber range** built as Infrastructure as Code on a 6-node
Proxmox cluster. It exists to practice offensive **and** defensive techniques,
develop bespoke tooling and detections for Linux and Windows, and to study CVEs & malware safely.

<div align="center">

## Components

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
| 🐛 **CVE testing** | Ephemeral victims with `clean-baseline` snapshots, repeatable, rollback-friendly. |

</div>

## Getting started

- **[Bring-up runbook](_docs/runbooks/security-lab-bring-up.md)** — the ordered Phase 0 → 2 build with verification gates.
- **[ADR-0009](_docs/decisions/0009-security-lab-segmentation.md)** — the segmentation design and why VLAN zones (not EVPN).
- **[`.claude/rules/lab-isolation.md`](.claude/rules/lab-isolation.md)** — the safety invariants to read before touching the range.
