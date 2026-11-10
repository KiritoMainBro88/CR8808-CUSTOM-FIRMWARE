# Security Engineering & Continuous Update Strategy

Please refer to the authoritative document at [`docs/SECURITY_UPDATE_STRATEGY.md`](docs/SECURITY_UPDATE_STRATEGY.md).

Contains:
1. Core Security Philosophy: Software Freshness vs. Continuous Security Maintenance.
2. Supply Chain Governance: Pinned sources, reproducible builds (`SOURCE_DATE_EPOCH`), SBOM generation.
3. Cargo & C Auditing: Automated vulnerability scanning, elimination of vulnerable dependencies (`atty`).
4. Hardened Defaults: WAN drop policy, key-based SSH, zero open management ports on WAN.
5. CVE Patching Cadence: Emergency 24-48h hotfix workflow, signed artifacts (`signify-openwrt`).
6. Failsafe Rollback: U-Boot bootcounter fallback, OverlayFS revert.
