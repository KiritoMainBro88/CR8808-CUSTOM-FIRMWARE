# Milestone M5 Build Reproducibility Report

- **Report ID:** `reports/M5_BUILD_REPRODUCIBILITY.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 dual Cortex-A53 @ 1.0 GHz)
- **Target OS:** OpenWrt 25.12.6 Stable / Linux Kernel 6.12.112 LTS
- **Package Manager:** `apk` (`apk-tools` v3)
- **Date:** 2026-11-11
- **Status:** Fully Reproducible PC Build Environment Documented

---

## 1. Reproducibility Standard & Environmental Controls

To ensure that any independent engineer or continuous integration runner can reproduce the exact bit-for-bit or functional equivalent of the Milestone M5 Daily Driver artifacts, the build pipeline enforces strict environmental determinism:

1. **`SOURCE_DATE_EPOCH` Clamping:** All timestamps in archives, SquashFS filesystems, and U-Boot FIT headers are fixed to the git commit timestamp, eliminating non-deterministic temporal jitter.
2. **Fixed Toolchain Versions:**
   - **Host Operating System:** Linux WSL2 Ubuntu 22.04 LTS (`6.6.87.2-microsoft-standard-WSL2` x86_64)
   - **Rust Toolchain:** `rustc 1.99.1 (58cf8f9c3 2026-10-13)` / `cargo 1.99.1 (5f94df478 2026-08-27)`
   - **Device Tree Compiler:** `dtc 1.6.1`
   - **SquashFS Utility:** `mksquashfs version 4.5 (2021/07/28)` with XZ compression support
   - **U-Boot Tools:** `mkimage version 2022.01+dfsg-2ubuntu2.9`
   - **MTD Tools:** `ubinize (mtd-utils) 2.1.4`
3. **Hermetic Rootfs Generation:**
   - File permissions, user IDs (`uid=0`), group IDs (`gid=0`), and inode ordering are clamped during `mksquashfs` invocation via `-root-owned -noappend`.

---

## 2. Step-by-Step Reproduction Instructions

From a clean checkout of `CR8808-CUSTOM-FIRMWARE` on Windows/WSL2:

### Step 1: Ensure Prerequisites in WSL2
```bash
wsl -d Ubuntu-22.04 -u root bash -c '
  apt-get update -y && \
  apt-get install -y build-essential device-tree-compiler squashfs-tools u-boot-tools mtd-utils python3 bc
'
```

### Step 2: Compile Patched BoringTun Userspace Binary
```bash
wsl -d Ubuntu-22.04 -u root bash -c '
  source /root/.cargo/env
  cd /root/work/boringtun-boringtun-cli-0.7.1
  cargo build --release --package boringtun-cli
'
```

### Step 3: Execute M5 Build Pipeline
```bash
wsl -d Ubuntu-22.04 -u root bash /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/scripts/build_m5_daily_driver.sh
```

### Step 4: Verify Cryptographic Hashes
```bash
cd /mnt/d/vibecode/CR8808-CUSTOM-FIRMWARE/artifacts/m5_build
sha256sum -c SHA256SUMS
```

---

## 3. Official Artifact Checksum Registry

| Artifact Filename | Purpose | Size | SHA256 Checksum |
|---|---|---|---|
| `ipq5018-xiaomi-cr8818-daily.dts` | Clean DSA Daily DTS | 4.8 KB | `32a8d9cbcaa78e5d6a00cfebf6f0b73b6c36836a3db76d3fe447a672de70ff10` |
| `ipq5018-xiaomi-cr8818-daily.dtb` | Compiled DTB Blob | 26,788 B | `56fe7befb6bf05b81eaa0d305793f51f6e85705d4a798db4cf612be3ba378edd` |
| `kernel-6.12.112.config` | Kernel 6.12 LTS Config | 2.1 KB | `0e08633f672db27ed8bcbfac1c636220cad24d4bc4c0856e1d58f67edbd30372` |
| `uImage.itb` | U-Boot FIT Image | 4,223,676 B | `514bf364383925d8b2056aefcfbd4cd8d9f0333cda5b118168a73068701e131c` |
| `openwrt-25.12.6-...rootfs.squashfs` | XZ SquashFS Rootfs | 573,440 B | `1e92df9cf8592d082f4e6352970c1523958ca2b54330d650d3082100a04f99b6` |
| `openwrt-25.12.6-...factory.ubi` | Factory NAND UBI Image | 5,373,952 B | `b7e61f3ec9aa3c17f5771d0f4e3ec0e764fb7caab1386b7fa8e51b5f4e3f3250` |
| `openwrt-25.12.6-...sysupgrade.bin` | Sysupgrade Archive | 4,802,560 B | `6983cfc15ff935d24cb1f79b7e133d9914fda4d0c08618388fa8ea6e4c7a017c` |

All artifacts generated are self-contained and reproducible on any modern Linux host equipped with `dtc`, `mksquashfs`, `mkimage`, and `ubinize`.
