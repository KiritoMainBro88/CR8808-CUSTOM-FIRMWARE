# 03 — Initial System Architecture

Status: Candidate architecture. No base platform approved.

## Architectural principles
- Exact hardware compatibility before kernel-version preference.
- Keep upstream repositories separate and pin exact commits.
- Integrate small patches with provenance.
- Build and inspect on PC before device interaction.
- Preserve stock firmware as baseline.
- Measure before tuning.
- Do not infer Xiaomi proprietary feature parity.

## Candidate source roles
- zcop ImmortalWrt: candidate CR881x board/DTS and YT921x switch reference.
- kuncy7 OpenWrt NSS EDMA: NSS/ECM/ath11k/qdisc reference.
- kuncy7 NSS packages: NSS driver/package reference.
- OpenWrt upstream: kernel/networking/package foundation.
- ImmortalWrt upstream: distribution/package alternative.
- fanha99 CR8806 NSS: CR8806 porting reference only.
- hzyitc Redmi AX3000: legacy IPQ50xx/QSDK reference.
- marchmin zcop fork: YT9215 register reference.

These are candidates, not confirmed compatible sources.

## Base platform decision
Compare kernel/API, DTS, GPIO/reset/power sequencing, MDIO, switch DSA, Ethernet MAC/EDMA, NSS firmware ABI, ECM, qdiscs, ath11k/mac80211 integration, package ecosystem, memory footprint, security cadence and board-specific changes.

Do not blindly merge zcop and kuncy7. A possible architecture is to use the closest proven CR881x hardware base and selectively port NSS components, but this remains a hypothesis until source audit and tests.

## Integration repository model
This repository owns:
- source manifest and locked revisions;
- device target configuration;
- project-owned patches;
- package/service integration;
- test plans and scripts;
- release manifests and documentation.

Upstream source checkouts should be separate worktrees or source cache, not copied wholesale into the product repository.

## WireGuard target architecture
Target end state: BoringTun Rust only.
Migration order:
1. Package Rust daemon and service on PC.
2. Validate build/link dependencies and UAPI behavior.
3. Later, after explicit router test authorization, use an isolated interface/port.
4. Validate real peer handshake, bidirectional traffic, DNS, MTU, reconnect, restart, CPU/RSS, latency and soak.
5. Validate boot ordering and firewall.
6. Approve Rust as primary.
7. Remove Go service only after all acceptance criteria pass and rollback is available.

## Wi-Fi architecture
Preserve 5 GHz HE160. Verify radio, driver, firmware, board data/calibration, antenna chains and regulatory domain. Test OFDMA/MU-MIMO only where the driver has documented support and client interoperability is confirmed.

## Performance architecture
Track CPU per core, softirq, NSS counters, throughput, loaded latency percentiles, packet loss, RAM pressure, slab, OOM/allocstall, temperature, Wi-Fi retries/airtime and WireGuard resources. No blanket sysctl/RPS/RFS/IRQ/backlog changes without measurement.
