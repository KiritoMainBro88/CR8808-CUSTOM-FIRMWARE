# BoringTun 60-Minute Soak Test â€” Completion Report

- **Report:** `reports/SOAK_60M_COMPLETION_REPORT.md`
- **Author:** `soak-monitor` (AI swarm worker)
- **Classification:** `PC_VERIFIED` / `NON_FLASHABLE_TEST_ARTIFACT` (x86_64 WSL2 network namespaces; **not** run on CR8808/CR8818 hardware, which remains `HARDWARE_BLOCKED`)
- **Test script:** `tests/integration/soak_boringtun_60m.sh 3600` (SHA-256 `7d01fecbb6ce1c969192ca841cf90c7f3a2edb86cf4032371847adc444b46d5c`)
- **Daemon:** `boringtun-cli 0.7.1`, 2 instances (`wg_soak0` router / `wg_soak1` peer), `--threads 2`, in separate netns joined by a veth pair
- **Started:** 2026-11-11T04:04:41Z, **Completed:** ~2026-11-11T05:04:45Z

## 1. Result

| Metric | Value |
|---|---|
| Configured duration | 3600 s |
| Measured soak time | **3600 s (60 min 0 s)** |
| Total ICMP probes sent | **2907** (Râ†’P every ~1.5 s, plus Pâ†’R every 5th probe) |
| Probes lost | **0** (0.0000 %) |
| `[SOAK ALERT]` lines in log | **0** |
| Rekey cycles detected | **29** |
| Live UAPI peer mutations (keepalive, under traffic) | **11**, all succeeded, no panic |
| VmRSS initial â†’ final | **2880 kB â†’ 2880 kB (0 kB growth)** |
| VmRSS in all 117 progress samples | 2880 kB (0 samples differed) |
| Daemon deaths | 0 |
| Script exit code | 0 |

## 2. Rekey cycles

Detection compares `wg show latest-handshakes` age before/after: a rekey is counted when age drops from â‰¥60 s to <15 s. Observed interval is consistently ~120â€“125 s, matching the WireGuard REKEY_AFTER_TIME of 120 s.

| # | T (s) | Age reset | # | T (s) | Age reset | # | T (s) | Age reset |
|---|---|---|---|---|---|---|---|---|
| 1 | 119 | 119â†’0 | 11 | 1348 | 119â†’1 | 21 | 2581 | 119â†’1 |
| 2 | 240 | 119â†’0 | 12 | 1472 | 120â†’1 | 22 | 2704 | 119â†’0 |
| 3 | 362 | 119â†’0 | 13 | 1594 | 119â†’0 | 23 | 2826 | 119â†’1 |
| 4 | 483 | 118â†’0 | 14 | 1719 | 119â†’1 | 24 | 2949 | 118â†’0 |
| 5 | 607 | 119â†’0 | 15 | 1841 | 118â†’0 | 25 | 3073 | 119â†’0 |
| 6 | 730 | 118â†’0 | 16 | 1966 | 119â†’0 | 26 | 3194 | 118â†’0 |
| 7 | 854 | 119â†’0 | 17 | 2090 | 119â†’1 | 27 | 3319 | 119â†’0 |
| 8 | 978 | 119â†’0 | 18 | 2213 | 118â†’0 | 28 | 3444 | 119â†’1 |
| 9 | 1102 | 120â†’1 | 19 | 2337 | 119â†’0 | 29 | 3567 | 119â†’0 |
| 10 | 1224 | 119â†’0 | 20 | 2458 | 118â†’0 | | | |

Packet delivery continued across every rekey with no probe loss.

## 3. UAPI mutations under live traffic (Issue #498)

One `wg set ... persistent-keepalive N` every ~300 s, at T = 300, 601, 901, 1201, 1501, 1801, 2101, 2401, 2702, 3002, 3303 s (N = 21â€¦31). Each returned success with no daemon panic and no probe loss.

## 4. Artifact finalization and checksums

In `artifacts/m6_build/`:

| File | SHA-256 |
|---|---|
| `boringtun_soak_60m.log` (15,537 B) | `22130bc188d85952a76f52d891b92c1f3b8bd9407b0915bc59ff2d8334717bc6` |
| `boringtun_soak.log` (alias, identical) | `22130bc188d85952a76f52d891b92c1f3b8bd9407b0915bc59ff2d8334717bc6` |
| `boringtun_soak_60m_telemetry.json` (`status: COMPLETED`, `exit_code: 0`) | `acf7cda0f1bcc18ee0caf5ebb588c5bfdb3171aaff7669fc3dbd14e958bba89d` |
| `boringtun_soak_telemetry.json` (alias, identical) | `acf7cda0f1bcc18ee0caf5ebb588c5bfdb3171aaff7669fc3dbd14e958bba89d` |

- All four match their WSL sources `/tmp/boringtun_soak_60m.log` and `/tmp/boringtun_soak_telemetry.json` byte-for-byte.
- **Note:** the script copies the log to `artifacts/` *before* its final cleanup trailer (`[SOAK CLEANUP]` lines) is written by `tee`, so the auto-copied log was 82 bytes short. I re-copied the final `/tmp` log so the artifact is complete.
- `artifacts/m6_build/SHA256SUMS` soak entries (previously the stale hashes of an earlier short run) were updated and verified with `sha256sum -c` (4/4 OK). Only those four lines were changed.

## 5. Limitations (read before citing)

- ICMP probes only (~1 probe per 1.5 s); this is a **stability/rekey/leak soak, not a throughput test**. 2907 probes is a modest packet count.
- Host-only: x86_64 WSL2, veth between netns. It proves protocol/timer/memory behavior of BoringTun 0.7.1, **not** performance or stability on the IPQ5018 Cortex-A53 (`ACCEPTANCE_TARGET` pending hardware).
- VmRSS is sampled every 30 s on the router-side daemon only (peer not sampled); the constant 2880 kB is a coarse page-granular figure.
- Rekey count is inferred from handshake-age resets, not from daemon-internal counters.
- Probe-loss accounting relies on `ping -W 1`; a >1 s stall would register as a drop (none occurred).

## 6. Verdict

The full 3600-second soak completed with **0 dropped probes, 29 successful rekeys, 11 live UAPI mutations without panic, and 0 kB VmRSS growth**. The 60-minute soak status can move from `IN PROGRESS` to `PC_VERIFIED`.
