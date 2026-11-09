# 01 — User Requirements Specification

Status: Draft; requirements must be traced to tests.

## Functional requirements

| ID | Requirement | Priority | Acceptance evidence |
|---|---|---|---|
| FR-001 | Exact support for Xiaomi CR8808 Ver.B | MUST | Verified board, DTS, SoC, switch and radios |
| FR-002 | All required Ethernet ports operate correctly | MUST | Per-port link, duplex, throughput, VLAN and error tests |
| FR-003 | 5 GHz HE160/160 MHz remains available | MUST | Client association and sustained test |
| FR-004 | 2.4 GHz Wi-Fi works | MUST | Association and stability |
| FR-005 | NSS acceleration is evaluated | MUST | Hardware counters + controlled A/B benchmark |
| FR-006 | BoringTun Rust becomes primary WireGuard | MUST | Real peer handshake, bidirectional traffic, reconnect, soak |
| FR-007 | Go WireGuard is removed after Rust acceptance | MUST | Migration and rollback evidence |
| FR-008 | QoS/SQM does not cause unacceptable regressions | MUST | Loaded latency + throughput |
| FR-009 | Stability under sustained load | MUST | RAM, CPU, thermal, OOM, allocstall and uptime evidence |
| FR-010 | Required WAN/LAN services continue to work | MUST | DHCP, PPPoE, DNS, NAT, VLAN, IPv6 as used |
| FR-011 | Xiaomi features are inventoried | MUST | Feature parity matrix |
| FR-012 | Build can be reproduced | MUST | Locked source/config/toolchain and repeat build |
| FR-013 | No persistent install without independent recovery | MUST | Approved recovery plan + explicit GO |

## Deep optimization areas
1. CPU and per-core utilization.
2. NSS/ECM fast path, exception path and firmware compatibility.
3. Ethernet MAC/EDMA/switch topology and VLAN.
4. Wi-Fi HE160, airtime, OFDMA, MU-MIMO, retransmissions and client interoperability.
5. RAM pressure, slab, allocation failures and OOM.
6. IRQ/SoftIRQ distribution and packet processing.
7. WireGuard throughput, latency, CPU, RSS, handshake and reconnect.
8. QoS/SQM and bufferbloat.
9. DNS, routing, MTU and firewall efficiency.
10. Security patch cadence and package footprint.

Every optimization must have baseline, hypothesis, one-variable experiment, measurement, rollback and regression result.

## Explicit user constraints
- Do not default to 80 MHz; preserve 160 MHz requirement.
- No UART available to the owner.
- Do not interrupt current LAN/Internet during PC-only work.
- Do not keep Go as permanent WireGuard service; transition to Rust after validation.
- Do not promise 100% Xiaomi feature parity without evidence.
