# BoringTun Rust WireGuard Integration Test & Empirical Audit Report

Please refer to the authoritative report at [`reports/BORINGTUN_INTEGRATION_TEST_REPORT.md`](reports/BORINGTUN_INTEGRATION_TEST_REPORT.md).

Contains:
1. Full security audit of BoringTun 0.7.1 upstream (nonce overflow fix, atty CVE-2021-45710 removal).
2. Deep investigation of Issue #495 (one-way deaf regression in library usage) and proof of immunity in `boringtun-cli`.
3. Verbatim test logs from real Linux network namespace test in WSL2:
   - Initial handshake & bi-directional ping (IPv4 & IPv6).
   - 20s and 35s idle soak proving zero packet loss and absence of Issue #495.
   - 10-second TCP `iperf3` throughput: **949 Mbps line rate** (1.10 GB transferred).
   - Physical memory measurement: **3.0 MB VmRSS** (under 15 MB budget) with zero leak under load.
   - Dynamic link failure and auto-reconnection test.
4. Critical discovery: BoringTun UAPI relative timestamp idiosyncrasy and the dual-mode fix implemented in `boringtun_watchdog`.
