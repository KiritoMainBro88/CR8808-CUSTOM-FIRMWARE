# BoringTun Rust WireGuard Integration Test & Empirical Audit Report

Please refer to the authoritative report at [`reports/BORINGTUN_INTEGRATION_TEST_REPORT.md`](reports/BORINGTUN_INTEGRATION_TEST_REPORT.md).

### Summary of Audited Results & Engineering Deliverables:
1. **Upstream Security Fixes Verified:** Nonce overflow fix, atty (CVE-2021-45710) elimination, zero vulnerability advisories.
2. **Issue #498 (UAPI Peer Update Panic) Solved:**
   - Root cause identified in `boringtun/src/device/mod.rs:321` (panic on modifying existing peer).
   - Authored and validated patch `0002-boringtun-uapi-peer-update-no-panic.patch`.
   - Empirically proven: In-place `wg set` update executed with exit code 0, 0% packet loss, zero process death.
3. **Issue #495 Resistance & Multi-Cycle Reconnection:**
   - 20s and 35s idle soak tests completed with 0% packet loss.
   - 3 consecutive physical link outages tested; 100% recovered within 1.5 seconds.
4. **Multi-Peer & Routing Verification:**
   - Dual-peer simultaneous traffic verified across independent namespaces.
   - Remote subnet (`192.168.200.0/24`) forwarding verified.
   - `replace_peers=true` atomic synchronization verified via `wg setconf`.
5. **Audited Empirical Metrics (WSL2 Host Environment):**
   - Host Throughput: 859.95 Mbps (`HOST_BENCHMARK` on x86_64 host CPU; router target is `ACCEPTANCE_TARGET`).
   - Host Process Memory: 2.8 MB idle / 3.0 MB loaded (`HOST_PROCESS_RSS`).
   - Retraction: All claims of "freeing 145 MB RAM" permanently removed. Router RAM classified strictly as `ESTIMATE`.
   - Script SHA256: `e60a28ce0f59712c155a030002262861e067c41c6c0daac2d18eb8da19e6e5b3` (85s test duration, exit code 0).
