# Contributing & Repository Governance

This document defines the contribution workflow, branching model, pull request process, architecture governance, licensing, and build reproducibility guidelines for **CR8808-CUSTOM-FIRMWARE**.

---

## 1. Branching Strategy

The repository follows a structured Git workflow to ensure safety, traceability, and stability:

- **`main`**: Production-ready, stable, and verified releases. No direct commits are permitted. Merges to `main` require full verification and explicit owner approval.
- **`develop`**: Central integration branch. All reviewed features, patches, and reports are integrated here before release staging.
- **`feature/<name>`**: Feature development branches created from `develop` (e.g., `feature/boringtun-service`, `feature/yt9215-dsa`).
- **`research/<name>`**: Research, upstream analysis, and benchmark exploration branches (e.g., `research/p1-upstream-audit`).
- **`fix/<name>`**: Bug fixes addressing specific test failures or regressions.

---

## 2. Commit Message Standards

All commits must follow the **Conventional Commits** specification:

- `feat:` A new feature, driver integration, or package addition.
- `fix:` A bug fix or patch correction.
- `docs:` Documentation updates, discovery reports, or architecture records.
- `refactor:` Code reorganization that does not alter behavior.
- `test:` Test scripts, automated benchmarks, or verification suites.
- `chore:` Repository maintenance, manifest updates, or ignore file changes.

**Format:**
```text
<type>(<scope>): <short summary in imperative mood>

[optional body explaining problem, root cause, and evidence]

Refs: <Task-ID or Requirement-ID>
```

---

## 3. Pull Request & Architecture Review Workflow

Every functional change must pass through the formal review hierarchy:

1. **Branch Creation:** Branch off `develop`.
2. **Implementation:** Keep changes minimal, atomic, and well-documented.
3. **Evidence Collection:** Record all verification commands, build logs, and test results.
4. **Public Security Review:** Verify no secrets, tokens, private keys, or internal credentials are committed.
5. **Architecture Review Gate:**
   - All cross-subsystem changes (kernel, switch DSA, NSS, memory layout, WireGuard migration) require review and sign-off by the **Architecture Lead (ChatGPT)**.
   - The user serves as the communication bridge, relaying technical findings and approvals.
6. **Merge to `develop`:** Fast-forward or non-fast-forward merge with a clean commit history. Rebase to keep history linear when applicable.

---

## 4. Upstream Integration & Patch Policy

When upstream repositories (`kuncy7/openwrt-nss-edma`, `zcop/immortalwrt`, `openwrt/openwrt`) receive updates:
- **Never blindly merge or overwrite the repository with an upstream snapshot.**
- Inspect the upstream commits, evaluate their impact on the CR8808 Ver.B hardware profile, and cherry-pick or adapt individual patches.
- Every imported patch must document:
  - Upstream source repository and commit SHA.
  - Original author and license.
  - Reason for inclusion and target subsystem.
  - Verification test result and clean rollback instructions.
- Pin exact upstream commit SHAs in `manifests/sources.lock.yaml`.

---

## 5. License Policy

- **Project Integration Code & Documentation:** Licensed under the GNU General Public License v2.0 (GPL-2.0) to maintain compatibility with the Linux kernel and OpenWrt ecosystem.
- **Upstream Code & Drivers:** Maintain existing upstream licenses (GPL-2.0 for Linux kernel and OpenWrt; dual GPL-2.0/BSD-3-Clause for Motorcomm drivers).
- **Rust Components:** BoringTun is licensed under Apache-2.0 / MIT.
- **Proprietary Binary Firmware Blobs:** Binary firmware (such as Qualcomm NSS firmware `retail_router0.bin` or `ath11k` board calibration binaries) must **never be committed directly** to the Git repository. They must be downloaded at build time via official recipes and license agreements.

---

## 6. Build Environment & Reproducibility Guide

To ensure build reproducibility across different environments:

### Prerequisites:
- **Host OS:** Windows 11 with WSL2 (Ubuntu 22.04 LTS) or native Linux x86_64.
- **Hardware Minimums:** 16 GB RAM (32 GB recommended), 4+ CPU cores, 50 GB free disk space on a case-sensitive filesystem.
- **Required Build Packages in Ubuntu 22.04:**
  ```bash
  sudo apt-get update && sudo apt-get install -y \
      build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
      gettext git libncurses5-dev libssl-dev python3-distutils rsync \
      unzip zlib1g-dev file wget curl
  ```
- **Rust Toolchain:** `rustc` and `cargo` (1.97+) for compiling BoringTun cross-targets.

### Reproducible Build Protocol:
1. Ensure the working tree is clean (`git status`).
2. Sync feeds from exact pinned revisions specified in `manifests/sources.lock.yaml`.
3. Apply project-owned patches from `patches/`.
4. Run `make defconfig` and verify `.config` matches target baseline.
5. Execute build with parallel job limits matching system memory (`make -j$(nproc)`).
6. Verify output hash against `artifacts/` manifest.
