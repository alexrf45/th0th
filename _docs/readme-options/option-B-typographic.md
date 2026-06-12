<!-- ============================================================
     OPTION B — Wordmark + monospace typographic subtitle.
     Banner art on top, then the name as an H1, then a terminal-
     feel tagline using <samp> + middot separators. Best when the
     banner is *art only* (no wordmark baked in).
     ============================================================ -->

<div align="center">

<img src="https://github.com/user-attachments/assets/66fcda90-452a-4ebe-996f-4ac9aff82281" alt="" width="820" />

# th0th

<samp>offense&nbsp;·&nbsp;defense&nbsp;·&nbsp;everything between&nbsp;—&nbsp;fully isolated</samp>

<br/>

<a href="https://th0th.dev"><img src="https://img.shields.io/badge/th0th.dev-1A1A1A?style=flat-square&logo=cloudflare&logoColor=white" alt="th0th.dev" /></a>

</div>

---

`th0th` is a self-hosted **cyber range** built as Infrastructure as Code on a 6-node
Proxmox cluster. It exists to practice offensive **and** defensive techniques, develop
bespoke tooling and detections for Linux and Windows, and to study CVEs & malware —
inside networks isolated at the hypervisor, so nothing detonated can reach the home or
management network.

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
