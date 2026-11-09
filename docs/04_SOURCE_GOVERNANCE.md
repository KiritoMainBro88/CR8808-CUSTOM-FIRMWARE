# 04 — Upstream Source Governance

## Audited repositories (Status: 2026-11-09)

| Alias | URL | Audited Commit | Role | Disposition |
|---|---|---|---|---|
| zcop | https://github.com/zcop/immortalwrt | `c5ad88b` | CR881x Board DTS & YT9215S DSA Driver | **Primary Hardware Reference** |
| kuncy7-nss-packages | https://github.com/kuncy7/nss-packages | `c94a780` | NSS Firmware & Drivers Feed | Priority NSS Reference |
| kuncy7-nss-edma | https://github.com/kuncy7/openwrt-nss-edma | `047ee4c` | stmmac claim API & 256M tuning | Architectural Reference Only |
| openwrt | https://github.com/openwrt/openwrt | `dd72c4c` | Upstream Mainline Baseline | Upstream Comparison Base |
| immortalwrt | https://github.com/immortalwrt/immortalwrt | `4765b65` | Distribution Base | Distribution Upstream |
| fanha99-cr8806 | https://github.com/fanha99/openwrt-xiaomi-cr8806-nss | `1469a4a` | CR8806 reference | Incompatible (QCA8337) |
| hzyitc | https://github.com/hzyitc/openwrt-redmi-ax3000 | `6faaa15` | Legacy IPQ50xx (Kernel 5.15) | Superseded |
| marchmin-zcop | https://github.com/marchmin/immortalwrt-zcop | `7740308` | YT9215 register archive | Superseded |

URLs, branch names and repository availability must be verified during P1. Do not invent commit IDs.

## Source audit checklist
For each source record:
- URL, owner, default branch, tags/releases;
- latest commit SHA and date at audit time;
- license and redistribution constraints;
- kernel version, toolchain, target architecture and ABI;
- device target/profile and DTS path;
- switch driver, Ethernet/EDMA, GPIO/reset and MDIO paths;
- NSS core, firmware, ECM, qdisc and Wi-Fi integration paths;
- known issues, CI/build instructions and relevant PRs;
- differences from upstream;
- whether changes are merged upstream or maintained only in fork.

## Integration policy
- No blind merge of entire repositories.
- Prefer small cherry-picks or project-owned patches.
- Every imported change records source commit, author, license, purpose, dependency, test and revert.
- Never copy binary firmware blobs without provenance and license review.
- Pin exact commits in `manifests/sources.lock.yaml`.
- Upstream update is a candidate, not an automatic release.

## Branch policy
- `main`: reviewed and releasable.
- `develop`: integration branch.
- `feature/<topic>`: isolated implementation.
- `research/<topic>`: source/architecture investigation.
- `fix/<topic>`: corrective work.

No direct commits to main; no force push.
