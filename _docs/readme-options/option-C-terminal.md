<!-- ============================================================
     OPTION C — Terminal aesthetic. ASCII wordmark in a <pre> block
     INSTEAD OF the painterly banner (don't stack both — it gets
     busy). Leans into the hacker/range identity; stays pure
     Markdown + HTML, no image hosting needed.
     ============================================================ -->

<div align="center">

<pre>
 _   _      ___  _   _
| |_| |__  / _ \| |_| |__
| __| '_ \| | | | __| '_ \
| |_| | | | |_| | |_| | | |
 \__|_| |_|\___/ \__|_| |_|
</pre>

<samp>:: a self-hosted cyber range&nbsp;—&nbsp;offense · defense · everything between ::</samp>

<br/>

[![th0th.dev](https://img.shields.io/badge/th0th.dev-1A1A1A?style=flat-square&logo=cloudflare&logoColor=white)](https://th0th.dev)
&nbsp;![status](https://img.shields.io/badge/range-armed-C9252A?style=flat-square)
&nbsp;![build](https://img.shields.io/badge/build-phase_2-2EA44F?style=flat-square)

</div>

---

```console
$ whoami
th0th — a security research range built as Infrastructure as Code on a 6-node
        Proxmox cluster: practice offense AND defense, develop bespoke tooling
        and detections for Linux/Windows, and study CVEs & malware — inside
        networks isolated at the hypervisor, so nothing detonated can reach the
        home or management network.
```

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

## Safety & scope

> Authorized, personal, and isolated. Detonation networks have **no gateway** — no route
> to the home / management LAN, TrueNAS, the internet, or each other, even if a victim is
> fully compromised. Scenario disks stay **node-local**; nothing vulnerable touches the
> NAS. Invariants: [`.claude/rules/lab-isolation.md`](../../.claude/rules/lab-isolation.md).

## Getting started

- **[Bring-up runbook](../runbooks/security-lab-bring-up.md)** — the ordered Phase 0 → 2 build with verification gates.
- **[ADR-0009](../decisions/0009-security-lab-segmentation.md)** — the segmentation design and why VLAN zones (not EVPN).
- **[`.claude/rules/lab-isolation.md`](../../.claude/rules/lab-isolation.md)** — the safety invariants to read before touching the range.
