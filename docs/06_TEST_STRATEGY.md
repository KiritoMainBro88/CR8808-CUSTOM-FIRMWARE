# 06 — Verification and Test Strategy

## Test levels
- L0: source, license, DTS, config, dependency and image static validation.
- L1: clean PC build and repeatability.
- L2: image format, metadata, partition expectations and checksum inspection.
- L3: non-persistent device test only if a supported RAM/initramfs path and safe recovery are proven for this exact board.
- L4: persistent installation only after separate GO decision and independent recovery validation.

If safe RAM boot is not proven, stop at L2. Do not improvise UART or bootloader procedures.

## Test matrix
| ID | Area | Required evidence |
|---|---|---|
| HW-001 | Boot | cold/warm boot, watchdog, uptime, fallback |
| ETH-001 | Ethernet | each port link, duplex, throughput, errors |
| ETH-002 | Switch | chip ID, VLAN, FDB, bridge, counters |
| WAN-001 | WAN | DHCP/PPPoE/static as used, DNS, NAT |
| NET-001 | IPv4/IPv6 | DHCP, DNS, routing, firewall |
| WIFI-001 | 2.4 GHz | association, throughput, stability |
| WIFI-002 | 5 GHz HE160 | width, association, sustained throughput, retries |
| WIFI-003 | Wi-Fi 6 | OFDMA/MU-MIMO only if documented and client-supported |
| NSS-001 | NSS | module/firmware, hardware counters, exception path, CPU comparison |
| WG-001 | WireGuard | real peer handshake and bidirectional traffic |
| WG-002 | Rust service | restart, reconnect, MTU, DNS, RSS/CPU and soak |
| PERF-001 | Latency | idle/loaded RTT P50/P95/P99, jitter, packet loss |
| PERF-002 | Throughput | TCP/UDP, one/multiple streams, LAN/WAN |
| MEM-001 | Memory | MemAvailable, slab, pressure, OOM, allocstall |
| THERM-001 | Thermal | temperature during sustained load |
| FEAT-001 | Xiaomi parity | feature-by-feature status |
| SEC-001 | Security | versions, advisories, exposed services, firewall |

## Benchmark rules
- Compare against stock RA82 with same client, cable, location, channel and duration.
- Record raw logs, timestamps, tool versions and configuration.
- Change one variable per experiment.
- Do not use average ping only; report tail latency.
- Do not use a single iperf result as stability proof.
- Distinguish Go `VmSize` from `VmRSS`; do not assert GC pressure without runtime metrics and reproduction.
- No numeric acceptance threshold is invented here. Establish baseline first, then agree thresholds.

## Evidence output
Every test report uses `docs/templates/TEST_REPORT_TEMPLATE.md`.
