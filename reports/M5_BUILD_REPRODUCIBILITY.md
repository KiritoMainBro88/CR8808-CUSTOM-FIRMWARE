# Milestone M5 Build Reproducibility Report

- **Report ID:** `reports/M5_BUILD_REPRODUCIBILITY.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 dual Cortex-A53 @ 1.0 GHz)
- **Target OS:** OpenWrt 25.12.6 Stable / Linux Kernel 6.12.112 LTS
- **Package Manager:** `apk` (`apk-tools` v3)
- **Build Stage:** `M5A_PACKAGING_SKELETON_VERIFIED` (`NON_FLASHABLE_TEST_ARTIFACT`)
- **Date:** 2026-11-11
- **Status:** Fully Reproducible PC Packaging & Artifact Verification Documented (Non-Flashable Skeletons)

> [!WARNING]
> **NON-FLASHABLE TEST ARTIFACTS:**
> Images documented herein (`factory.ubi` and `sysupgrade.bin`) are strictly non-flashable packaging skeletons (`M5A_PACKAGING_SKELETON_VERIFIED`). Do not attempt to flash to hardware. Real distribution firmware is built in Milestone M6.

---

## 1. Reproducibility Standard & Environmental Controls

To ensure that any independent engineer or continuous integration runner can reproduce the exact packaging and functional artifacts of Milestone M5, the build pipeline enforces strict environmental controls:

1. **Fixed Toolchain Versions:**
   - **Host Operating System:** Linux WSL2 Ubuntu 22.04 LTS (`6.6.87.2-microsoft-standard-WSL2` x86_64)
   - **Rust Toolchain:** `rustc 1.99.1 (58cf8f9c3 2026-10-13)` / `cargo 1.99.1 (5f94df478 2026-08-27)`
   - **Device Tree Compiler:** `dtc 1.6.1`
   - **SquashFS Utility:** `mksquashfs version 4.5 (2021/07/28)` with XZ compression support
   - **U-Boot Tools:** `mkimage version 2022.01+dfsg-2ubuntu2.9`
   - **MTD Tools:** `ubinize (mtd-utils) 2.1.4`
2. **Hermetic Rootfs Generation:**
   - File permissions, user IDs (`uid=0`), group IDs (`gid=0`), and inode ordering are clamped during `mksquashfs` invocation via `-root-owned -noappend`.
3. **Packaging Scope & Limitations (Honest Disclosure):**
   - The compiled DTB (`ipq5018-xiaomi-cr8818-daily.dtb`) is an authentic binary compiled by `dtc` from authoritative DTS bindings.
   - The BoringTun daemon (`boringtun-cli 0.7.1`) is an authentic native/cross-compiled executable with signalfd fallback and UAPI patch 0002.
   - The kernel payload inside `uImage.itb` is currently a 4MB synthetic test payload used to validate FIT image structure and U-Boot parsing. Full Linux 6.12.112 LTS cross-compilation requires the OpenWrt buildroot toolchain.
   - The rootfs is a packaging prototype (0.54 MB) containing real OpenWrt configuration files, netifd scripts, and watchdog, with dummy placeholder stubs for base POSIX utilities.

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
  export PATH=/root/.cargo/bin:/usr/bin:/bin:$PATH
  cd /root/work/boringtun-boringtun-cli-0.7.1
  cargo build --release --bin boringtun-cli
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
| `uImage.itb` | U-Boot FIT Image (Prototype) | 4,223,676 B | `b275d8c59ccfbcbd1e4c06c932d43e7db053be0aa72bd22d8bc3f61d5f775313` |
| `openwrt-25.12.6-...rootfs.squashfs` | XZ SquashFS Rootfs Prototype | 573,440 B | `c9b341bd57cef349366ef1b8976e0a1b7b6a5ea550f49c8b83e6464f65f93543` |
| `openwrt-25.12.6-...factory.ubi` | Factory NAND UBI Image | 5,373,952 B | `e8c8f6ffb31531982508a25cd927b5e604fbcae650ec79170cbc06abcc33554a` |
| `openwrt-25.12.6-...sysupgrade.bin` | Sysupgrade Archive | 4,802,560 B | `e7b95da215bf449818b6fe3a1936ff69aff0485a0d1bc3a21c5a7756ad90248d` |

All artifacts generated are self-contained and reproducible on any modern Linux host equipped with `dtc`, `mksquashfs`, `mkimage`, and `ubinize`.
