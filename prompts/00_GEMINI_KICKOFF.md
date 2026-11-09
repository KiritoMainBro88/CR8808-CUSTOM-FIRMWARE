# PROMPT 00 — Gemini Project Kickoff (P0/P1 only)

Paste this prompt into the EXISTING Gemini conversation. Do not create a new conversation yet.

---

You are the implementation/workstation agent for `CR8808-CUSTOM-FIRMWARE`.

Project root:
`D:\vibecode\CR8808-CUSTOM-FIRMWARE`

Existing lab workspace:
`D:\vibecode\test_wifi`

Before any action, read:
- `AGENTS.md`
- `GEMINI.md`
- `README.md`
- `PROJECT_STATUS.md`
- `TASKS.md`
- all files under `docs/`
- relevant agent role files under `agents/`

## Mission
Execute P0 setup and P1 source/build-host discovery only. The goal is to produce an evidence-based compatibility report for architecture review.

## Work items

### P0-001 — Safe repository setup
- Confirm the project root.
- Check whether Git already exists; do not overwrite existing history.
- If not initialized, initialize Git in this project folder only.
- Create documented folders if missing.
- Check working tree and record initial commit only if the files are complete and reviewed locally.
- Do not touch `test_wifi`.

### P1-001 — Build host audit
Record:
- Windows version/build.
- CPU model and logical cores.
- Physical RAM and available RAM.
- Free disk space on target build volume.
- WSL2 status and installed distributions.
- Linux kernel and distro version if available.
- Git, Python, make, gcc/clang, perl, rsync, unzip, wget/curl, file, sha256sum versions if installed.
- Whether virtualization is enabled and whether Docker is present.
Do not install, upgrade or configure anything. Do not run a full firmware build.

### P1-002 — Upstream source audit
Audit candidate repositories from `manifests/sources.yaml`.
For each repository record:
- repository URL, owner, default branch;
- latest commit SHA and date at audit time;
- tags/releases;
- license;
- kernel version, toolchain, architecture/ABI;
- target profile and board support;
- DTS paths and relevant commits;
- Ethernet/EDMA, switch, MDIO, GPIO/reset paths;
- NSS core/firmware/ECM/qdisc paths;
- Wi-Fi/ath11k/mac80211 integration;
- build instructions and known issues;
- whether suitable as base, reference only, unsuitable or unknown.

Do not invent any values. If repository cannot be accessed, record BLOCKED and the exact reason.

### P1-003 — Hardware compatibility analysis
Compare the CR8808 Ver.B evidence already documented with each candidate source.
Important:
- The commercial device is CR8808 Ver.B.
- Prior audits reported internal string `CR8818` and board `ap-mp03.3`, but these are not yet re-verified.
- Do not assume CR8806 image is compatible.
- Do not assume every CR881x device shares the same switch/radio/flash layout.
- Resolve whether switch is YT9215S or YT9215SC only if source evidence supports it.
- Identify unknowns and required read-only device checks for a later phase.
- Do not connect to the router in this task.

### P1-004 — Discovery report
Create:
`reports/2026-11-09/G1_DISCOVERY_REPORT.md`

Include:
1. Executive summary.
2. Build host readiness.
3. Source audit table.
4. Hardware/source compatibility matrix.
5. Kernel and driver conflicts.
6. NSS feasibility and unresolved ABI/firmware dependencies.
7. Switch/DSA feasibility.
8. Wi-Fi/HE160 feasibility.
9. Memory footprint concerns.
10. License/provenance issues.
11. Risks, unknowns and blocked items.
12. Recommendation with alternatives.
13. Questions requiring architecture review.
14. Exact sources, commit SHAs and raw evidence paths.

Use the source audit template in `docs/templates/SOURCE_AUDIT_TEMPLATE.md`.

## Strict prohibitions
- Do not SSH into the router.
- Do not run router commands.
- Do not upload files to the router.
- Do not change `test_wifi`.
- Do not install tools or packages.
- Do not build firmware.
- Do not merge repositories.
- Do not write patches.
- Do not stop Go WireGuard.
- Do not change network configuration.
- Do not flash, reboot or write NAND/MTD/NVRAM/bootloader/bootconfig.

## Completion
Update `TASKS.md` and `PROJECT_STATUS.md` only with evidence-backed status.
Return the structured response required by `AGENTS.md`.
Then STOP. Wait for architecture review. Do not start P2.
