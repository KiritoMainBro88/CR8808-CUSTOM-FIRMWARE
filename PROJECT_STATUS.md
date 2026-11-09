# Project Status

- Version: `0.1.0-dev.2`
- Date: 2026-11-09
- Phase: P1 Architecture Gate G1 Finalized (Round 4 Consistency & Hardware Audit) / P2 Preparation
- Current Branch: `feature/g1-corrections-round4`
- Overall status: `GATE_G1_CORRECTIONS_ROUND4_COMPLETE`
- GitHub remote: `https://github.com/KiritoMainBro88/CR8808-CUSTOM-FIRMWARE` (Active branches: `main`, `develop`, `review/g1-architecture-corrections`, `feature/g1-final-architecture-deliverables`, `feature/g1-corrections-round2`, `feature/g1-corrections-round3`, `feature/g1-corrections-round4`)
- Flash authorization: `NO-GO pending independent recovery validation`
- Initial Firmware Baseline: `CLEAN_DSA_LINUX_6.18_WITHOUT_NSS` (Approved)
- Primary Hardware Reference: `zcop/immortalwrt` (commit `c5ad88b`) — Approved for CR881x DTS & YT921x DSA
- Secondary NSS Reference: `kuncy7/nss-packages` & `kuncy7/openwrt-nss-edma` — Architectural reference for Phase 2
- WireGuard Target Engine: `BoringTun Rust` (Target ABI: `aarch64-unknown-linux-musl`; sole engine)
- Wi-Fi Target Mode: `5 GHz HE160 (160 MHz)` (Mandatory retention)
- Git History Remediation: `DRY_RUN_VALIDATED_CLEAN` (All commits verified 100% clean)
- Firmware build: `NOT_STARTED`
- Hardware validation: `NOT_STARTED`

## Confirmed via Owner & Prior Device Readback
- Commercial device: Xiaomi CR8808 Ver.B — `OWNER_CONFIRMED`.
- Internal model string: `CR8818` — `DEVICE_READBACK` (Certified via stock `ubus call system board` in prior audit).
- Board profile string: `ap-mp03.3` — `DEVICE_READBACK` (Certified via stock system readback).
- SoC: Qualcomm IPQ5018 dual-core Cortex-A53 — `DEVICE_READBACK`.
- Usable RAM: ~182 MB usable by Linux (`MemTotal`) — `DEVICE_READBACK`.
- Active Stock Firmware: Xiaomi RA82 Global v1.4.31 (Linux 4.4.60) — `DEVICE_READBACK`.
- Owner wants to preserve the current LAN/Internet connection during development — `OWNER_CONFIRMED`.
- Owner does not have UART and cannot independently recover a bricked router — `OWNER_CONFIRMED`.
- Existing lab workspace `D:\vibecode\test_wifi` preserved and untouched — `MEASURED`.
- Project workspace safely initialized at `D:\vibecode\CR8808-CUSTOM-FIRMWARE` on Git — `MEASURED`.
- GitHub repository synchronized: `main`, `develop`, and review branches live — `SOURCE_VERIFIED`.
- CR8806 firmware incompatibility verified: hardcodes QCA8337 switch at MDIO 0x17, incompatible with CR8808 Ver.B's Motorcomm YT9215S/SC switch — `SOURCE_VERIFIED`.
- `zcop/immortalwrt` approved as primary reference for CR881x board DTS, YT921x enhanced DSA driver, and GPIO39 reset — `OWNER_CONFIRMED` / Architecture Lead approved.
- History cleanup dry-run executed on isolated clone: 100% elimination of netbios hostname and private IPs verified — `MEASURED`.

## Reported / Unverified on-device
- Motorcomm switch physical silicon suffix: `UNKNOWN / REPORTED_UNVERIFIED` (YT9215S vs YT9215SC unconfirmed).
- GPIO 39 hardware function: DTS declares `reset-gpios`.
- Winbond W25N01GWZEIG NAND physical part marking.
- Xiaomi bootloader failover flags (`flag_try_sysX_failed`): `REPORTED_UNVERIFIED`.

## Current blockers
1. No verified recovery path independent of UART (Permanent constraint; flash remains `NO-GO`).
2. Git history sanitization application pending Product Owner final confirmation.
3. Read-only router baseline verification pending Architecture Lead authorization of [`docs/R0_READONLY_AUDIT_MANIFEST.md`](docs/R0_READONLY_AUDIT_MANIFEST.md).

## Status Transition Log
- 2026-11-09: Phase P0 and P1 completed. Initial G1 Discovery and GitHub Integration deliverables produced.
- 2026-11-09: ChatGPT Architecture Review received. Branch `review/g1-architecture-corrections` created. Git history security audit executed; technical report conclusions corrected; in-depth NSS comparative analysis authored; `manifests/sources.yaml` synchronized. Author: Gemini (Implementation Lead).
- 2026-11-09: Architecture Gate G1 conditionally approved. Baseline selected: Clean DSA Linux 6.18 without NSS. Git history dry-run executed on test clone (100% clean). Authored feature parity matrix, DSA baseline design, NSS experimental design, non-UART recovery architecture, and Class R0 read-only audit manifest. Deliverable: `reports/2026-11-09/FINAL_G1_ARCHITECTURE_DECISION.md`. Author: Gemini (Implementation Lead).
- 2026-11-09: Architecture Gate G1 Round 2 Corrections completed on branch `feature/g1-corrections-round2`. Disambiguated internal PHY `0x004dd0c0` from Motorcomm switch at `0x1d`; mapped DSA driver divergence (upstream vs zcop); rebuilt feature parity matrix with empirical taxonomy; corrected BoringTun target ABI to AArch64; overhauled recovery design with real Xiaomi boot flags and TFTP flash reality; refined R0 read-only manifest for QSDK tooling. Updated dry-run rewrite verified 100% clean across all 6 commits. Deliverable: `reports/2026-11-09/G1_REVIEW_ROUND2.md`. Author: Gemini (Implementation Lead).
- 2026-11-09: Architecture Gate G1 Round 3 Corrections completed on branch `feature/g1-corrections-round3`. Grounded switch port mapping in zcop reference DTS (P0-P2 LAN1-3, P3 WAN, P4 CPU2 dp1 internal GE PHY, P8 CPU1 dp2 SGMII 1000M, P10 MCU); removed erroneous 2500Base-X claims; investigated Issue #5 GPIO39 switch init bug (0xffff chip ID) and established 4-part 20-cycle reboot test protocol; separated upstream OpenWrt stmmac from zcop nss-dp dual-conduit; disambiguated DRAM BDF staging (0x4c400000/0x4d100000) from physical NAND 0:ART (0x780000); decoupled generic packages in parity matrix; established BoringTun Rust as sole WireGuard engine (in-kernel marked NOT_SELECTED); reconciled Git commit history evidence. Deliverable: `reports/2026-11-09/G1_REVIEW_ROUND3.md`. Author: Gemini (Implementation Lead).
- 2026-11-09: Architecture Gate G1 Round 4 Corrections completed on branch `feature/g1-corrections-round4`. Resolved DSA vs NSS architecture contradiction: Phase 1 defined strictly on upstream `dwmac-ipq5018` (`stmmac`) single-conduit SGMII 1000M Port 8 (zero NSS Datapath, Port 4 disabled); Phase 2 defined on `qcom,nss-dp` dual-conduit (`dp1`/`dp2`); performed deep analysis of Issue #5 GPIO 39 reset bug, rejecting userspace procd hook and designing 20-cycle reboot test; detailed Wi-Fi calibration pipeline from NAND 0:ART to DRAM and Q6 WCSS; decoupled unmeasured performance assertions from source availability in parity matrix; re-established `CR8818` and `ap-mp03.3` as `DEVICE_READBACK`; reinforced strict non-UART `NO-GO` on flashing. Deliverable: `reports/2026-11-09/G1_REVIEW_ROUND4.md`. Author: Gemini (Implementation Lead).
