# Source Manifest & Cryptographic Pinning Register

- **Document ID:** `docs/SOURCE_MANIFEST.md`
- **Milestone:** `M6 – Full OpenWrt Source Build & Hardening`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Internal Codename `CR8818`, Qualcomm IPQ5018 dual-core Cortex-A53 @ 1.0 GHz, 256MB DDR3L, Winbond W25N01GWZEIG 128MB SPI NAND, Motorcomm YT9215SC DSA, QCN6102 5GHz Wi-Fi 6 HE160)
- **Generated At:** 2026-11-11T10:05:00Z
- **Governance:** Zero-Ambiguity Source Lock

---

## 1. Upstream Base Distributions & Kernels

### 1.1 OpenWrt 25.12.6 Stable (Daily Driver Baseline)
- **Upstream Repository:** `https://git.openwrt.org/openwrt/openwrt.git`
- **Local Path in WSL2:** `/root/sources/openwrt-25.12.6`
- **Official Git Tag:** `v25.12.6`
- **Pinned Commit SHA:** `64900e756efa667774214f9c6b17c113222e01f7`
- **Commit Summary:** `OpenWrt v25.12.6: adjust config defaults`
- **Target Architecture:** `qualcommax / ipq50xx` (AArch64 Cortex-A53)
- **Package Management:** `apk` (`apk-tools` v3 musl native)

### 1.2 Linux Kernel 6.12.112 LTS (Daily Driver Kernel)
- **Source Archive:** `https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.12.112.tar.xz`
- **Upstream Release:** Linux 6.12.112 LTS (Long Term Support through Dec 2028)
- **OpenWrt Kernel Hash (`LINUX_KERNEL_HASH-6.12.112`):** `164dc9d1f6c93c61a15e1f071c48379b467f2b17c469cce7223471968208ed03`
- **Target Config:** `config/kernel-6.12.112-cr8818.config` (280 KB)
- **Compiler:** `gcc 11.4.0 / aarch64-linux-gnu-gcc`

### 1.3 Linux Kernel 6.18 LTS (Experimental Branch Only)
- **Role:** Research & Qualcomm NSS NPU Datapath Prototyping
- **Status:** Strictly isolated from Daily Driver release images

---

## 2. Reference Implementation Repositories

| Repository | Remote URL | Branch / Tag | Pinned Commit SHA | Role / Contribution |
|---|---|---|---|---|
| **Yangfl OpenWrt** | `https://github.com/yangfl/openwrt` | `cr8818` | `6729bbe9f082dc15449f17908832447caeec5065` | Xiaomi CR8818 Device Tree, partition layout, uboot-envtools mapping |
| **Zcop ImmortalWrt** | `https://github.com/zcop/immortalwrt` | `master` | `c5ad88b8d4ba2f3068fbf12f275a5015e718bc8e` | Motorcomm YT9215SC DSA driver source, registers & SerDes initialization |
| **Kuncy7 NSS EDMA** | `https://github.com/kuncy7/openwrt-nss-edma` | `main` | `a38f71c4b9213401ef94827d0912cb8592039841` | Qualcomm IPQ5018 NSS offload reference (Experimental track) |

---

## 3. WireGuard VPN Component: BoringTun Rust

### 3.1 Upstream Release Archive
- **Upstream Repository:** `https://github.com/cloudflare/boringtun`
- **Release Tag:** `boringtun-cli-0.7.1`
- **Tarball URL:** `https://github.com/cloudflare/boringtun/archive/refs/tags/boringtun-cli-0.7.1.tar.gz`
- **Tarball SHA256:** `0bfce9717e898533036c853e3433308770d9cd0a5f54b10e9d90f149947e355c`

### 3.2 Applied Patch Stack
1. `0001-update-cargo-edition-and-deps.patch`: Updates Cargo edition and pins compatible dependencies.
2. `0002-boringtun-uapi-peer-update-no-panic.patch`: Surgical in-place peer mutation fixing upstream Issue #498. Eliminates panic on existing peer updates without session key disruption; returns `libc::EOPNOTSUPP` (95) on unsupported mid-session mutations (e.g., PSK alteration).
3. `0003-reduce-idle-memory-and-buffer-pools.patch`: Optimizes thread pool and memory footprint for 256MB embedded profile (VmRSS ~2.88 MB).

### 3.3 Compiled Static Target Binary
- **Target Path:** `package/network/services/boringtun/files/boringtun-cli-aarch64`
- **Artifact Path:** `artifacts/m6_build/boringtun-cli-aarch64`
- **Target Triple:** `aarch64-unknown-linux-musl`
- **Binary Format:** ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked, stripped
- **Binary Size:** 1,178,176 bytes (~1.18 MB)
- **SHA256:** `1cdf830027d9c665263079ae726f47dc732f4fc2891dd1450c111596f6659d12`

---

## 4. OpenWrt Official Feeds

| Feed Name | Feed URL | Pinned Commit SHA | Primary Packages Selected |
|---|---|---|---|
| **packages** | `https://git.openwrt.org/feed/packages.git` | `093d551675b1119a06ef224d419905e8d6b2af1a` | `wireguard-tools`, `curl`, `jq`, `coreutils` |
| **luci** | `https://git.openwrt.org/project/luci.git` | `75a306df84a020c57a631ef5b4c02ace56d93387` | `luci`, `luci-base`, `luci-theme-bootstrap`, `rpcd`, `uhttpd` |
| **routing** | `https://git.openwrt.org/feed/routing.git` | `48c808034414a2112cf9d5261a20a320e8d0d170` | routing utilities, mesh helpers |
| **telephony** | `https://git.openwrt.org/feed/telephony.git` | `2618106d5846a4a542fdf5809f0d3ed228ce439b` | telephony frameworks (disabled by default) |
| **video** | `https://github.com/openwrt/video.git` | `094bf58da6682f895255a35a84349a79dab4bf95` | display frameworks (disabled by default) |
