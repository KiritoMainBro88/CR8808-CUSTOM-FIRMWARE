# OpenWrt PC Build Readiness & NSS Kbuild Audit Report

Please refer to the authoritative report at [`reports/OPENWRT_BUILD_READINESS_REPORT.md`](reports/OPENWRT_BUILD_READINESS_REPORT.md).

Contains:
1. Complete forensic post-mortem of M4 Kbuild failures (`dwmac-ipq5018.c`, `qca-nss-dp`, `upstream_yt921x.c`, `yt921x_enhanced.c`).
2. Verification of passing targets: `tag_yt921x.c` (clean DSA tagger), `tag_yt921x_8021q.c`, `tag_yt921x_enhanced.c`, `qca-dwmac-nss.ko`.
3. OpenWrt PC target image configuration for `DEVICE_xiaomi_cr8818`.
4. 128MB SPI NAND flash layout budget analysis.
5. Daily Driver package manifest (`daily_driver.defconfig`) and dry-run build instructions.
6. Zero-flash policy and strict NSS quarantine until physical bench validation.
