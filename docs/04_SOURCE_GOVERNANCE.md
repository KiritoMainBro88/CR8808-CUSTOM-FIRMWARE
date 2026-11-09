# 04 — Upstream Source Governance

## Candidate repositories

| Alias | URL | Intended role | Initial disposition |
|---|---|---|---|
| openwrt | https://github.com/openwrt/openwrt | Mainline base | Audit |
| immortalwrt | https://github.com/immortalwrt/immortalwrt | Distribution base | Audit |
| zcop | https://github.com/zcop/immortalwrt | CR881x/YT921x reference | Priority audit |
| kuncy7-nss-edma | https://github.com/kuncy7/openwrt-nss-edma | NSS integration | Priority audit |
| kuncy7-nss-packages | https://github.com/kuncy7/nss-packages | NSS packages/drivers | Priority audit |
| fanha99-cr8806 | https://github.com/fanha99/openwrt-xiaomi-cr8806-nss | CR8806 reference only | Reference |
| hzyitc | https://github.com/hzyitc/openwrt-redmi-ax3000 | Legacy IPQ50xx reference | Reference |
| marchmin-zcop | https://github.com/marchmin/immortalwrt-zcop | YT9215 register reference | Reference |

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
