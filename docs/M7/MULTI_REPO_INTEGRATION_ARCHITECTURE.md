# Multi-Repository Integration Architecture & Code Governance (M7.0)

- **Document ID:** `docs/M7/MULTI_REPO_INTEGRATION_ARCHITECTURE.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018 + Motorcomm YT9215SC + QCN6102)
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Complete Integration Blueprint for Gate M7.0

---

## 1. Executive Summary & Integration Principles

Milestone M7.0 mandates an explicit multi-repository integration model to combine the strengths of disparate upstream and community repositories while avoiding monolithic fork entanglement:
1. **Upstream First & Traceable Provenance:** Every kernel patch, driver backport, and Device Tree node must trace directly to a verified commit SHA from official OpenWrt, David Yang (`yangfl`), `zcop`, or `kuncy7`.
2. **Layered Separation of Concerns:** Core buildroot, target board definitions, out-of-tree patchsets, package feeds, and custom Rust services are isolated into modular layers.
3. **No Blind Merging:** Community repositories are never merged wholesale. Only audited, isolated components are imported as surgical patchsets or independent package feeds.

---

## 2. Layered Architecture Diagram

```
+=================================================================================================+
|                               LAYER 4: CUSTOM CR8818 USERSPACE & RUST                           |
|  - boringtun-cli 0.7.1 (AArch64 musl static, Patched Issue #498)                               |
|  - cr8818-watchdog, cr8818-telemetry, cr8818-cfgval, cr8818-led-daemon                         |
+=================================================================================================+
                                               |
+=================================================================================================+
|                               LAYER 3: PACKAGE FEEDS & ADD-ONS                                  |
|  - Official OpenWrt Feeds: packages, luci, routing, telephony                                   |
|  - Track B NSS Feed: kuncy7/nss-packages (qca-nss-drv, qca-dwmac-nss, ECM, FW 12.5)             |
|  - Custom Board Feed: feed-cr8818 (Rust daemons, board-specific uci-defaults)                   |
+=================================================================================================+
                                               |
+=================================================================================================+
|                               LAYER 2: BOARD SUPPORT & KERNEL PATCHSETS                         |
|  - Device Tree: ipq5018-cr8818.dts (yangfl authoritative CR8818 DTS)                            |
|  - Switch Driver & Patches:                                                                     |
|    * Patch 940: 940-net-dsa-yt921x-Abuse-SGMII-for-REVSGMII.patch (yangfl SerDes fix)          |
|    * Patch 967: YT9215SC mainline Linux 6.19 backport + zcop register fixes                     |
|    * Patch 0956: stmmac data-plane claim API (kuncy7, for Track B NSS)                         |
|  - Board Scripts: 02_network (board.d), 11-ath11k-caldata (hotplug 0:art extraction)            |
+=================================================================================================+
                                               |
+=================================================================================================+
|                               LAYER 1: BASE OPENWRT BUILDROOT                                   |
|  - Track A (Daily Driver): OpenWrt Official 25.12.6 LTS (Linux Kernel 6.12.112 LTS)             |
|  - Track B (Experimental): kuncy7/openwrt-nss-edma (OpenWrt main / Linux Kernel 6.18 LTS)       |
+=================================================================================================+
```

---

## 3. Layer Breakdown & Source Provenance

### 3.1 Layer 1: Base OpenWrt Buildroot
- **Track A (Daily Driver):** Sourced directly from `openwrt/openwrt` at commit `64900e7` (Release `v25.12.6`).
  - Kernel: Linux 6.12.112 LTS.
  - Package manager: `apk-tools` v3.
  - Target architecture: `qualcommax/ipq50xx`.
  - Toolchain: GCC 14.2 / musl libc.
- **Track B (Next-Gen Experimental):** Sourced from `kuncy7/openwrt-nss-edma` branch `c3po-tag-8021q` at commit `28ffd42`.
  - Kernel: Linux 6.18 LTS.
  - Implements the core NSS clocks, GCC fixes, and `stmmac` data-plane redirection.

### 3.2 Layer 2: Board Support & Target Patches
This layer injects hardware awareness for the Xiaomi CR8808 Ver.B into the buildroot:

1. **Target Image Profile (`target/linux/qualcommax/image/ipq50xx.mk`):**
   ```makefile
   define Device/xiaomi_cr8818
     $(call Device/FitImage)
     $(call Device/UbiFit)
     DEVICE_VENDOR := Xiaomi
     DEVICE_MODEL := CR8808 Ver.B / CR8818
     DEVICE_DTS := ipq5018-cr8818
     DEVICE_DTS_CONFIG := config@mp03.3
     BLOCKSIZE := 128k
     PAGESIZE := 2048
     NAND_SIZE := 128m
     DEVICE_PACKAGES := \
       ath11k-firmware-ipq5018 \
       ath11k-firmware-qcn6102 \
       ipq-wifi-xiaomi_cr8818 \
       boringtun-rust \
       kmod-nft-offload
   endef
   TARGET_DEVICES += xiaomi_cr8818
   ```

2. **Device Tree (`target/linux/qualcommax/dts/ipq5018-cr8818.dts`):**
   - Sourced from `yangfl/openwrt` (commit `6729bbe`).
   - Configures Motorcomm YT9215SC switch @ `0x1d` on MDIO1, reset on GPIO 39.
   - Configures LEDs on GPIOs 24-27 and Buttons on GPIOs 28, 38.
   - Configures reserved memory regions for TZ (`0x4ac00000`) and NSS (`0x40000000`).

3. **Kernel Patches (`target/linux/qualcommax/patches-6.12/` or `patches-6.18/`):**
   - `940-net-dsa-yt921x-Abuse-SGMII-for-REVSGMII.patch`: Intercepts `PHY_INTERFACE_MODE_SGMII` and remaps it to `YT921X_SERDES_MODE_REVSGMII` inside `yt921x_port_config()`.
   - `967-xx-net-dsa-yt921x-*.patch`: Backports mainline Linux 6.19 DSA driver and 802.1Q tagging support.
   - `0956-stmmac-add-data-plane-claim-API.patch` (Track B only): Enables NSS module data-plane handoff.

4. **Base System Scripts:**
   - `base-files/etc/board.d/02_network`: Automatically sets up DSA VLAN bridge and conduit interfaces (`wan` $\rightarrow$ Port 3; `lan` $\rightarrow$ Ports 0, 1, 2 on `eth1`).
   - `base-files/etc/hotplug.d/firmware/11-ath11k-caldata`: Extracts radio calibration data from `/dev/mtd13` (`0:art`):
     - Offset `0x1000` (128 KB) $\rightarrow$ `cal-ahb-c000000.wifi.bin`
     - Offset `0x26800` (128 KB) $\rightarrow$ `cal-ahb-b00a040.wifi1.bin`

### 3.3 Layer 3: Package Feeds & Upstream Sync
- **Official OpenWrt Feeds (`feeds.conf.default`):**
  - `src-git packages https://git.openwrt.org/feed/packages.git^<pinned_commit>`
  - `src-git luci https://git.openwrt.org/project/luci.git^<pinned_commit>`
  - `src-git routing https://git.openwrt.org/feed/routing.git^<pinned_commit>`
- **Track B NSS Feed (`nss_packages`):**
  - Sourced from `kuncy7/nss-packages` branch `ipq50xx-rebase` (`c94a780`).
  - Provides `kmod-qca-nss-drv`, `kmod-qca-dwmac-nss`, `kmod-qca-nss-ecm`, and `nss-firmware`.
- **Custom Board Feed (`feed-cr8818`):**
  - Local repository feed containing CR8818-specific packages, Rust binaries, and system tuning.

### 3.4 Layer 4: Rust Userspace Services
- Packaged as a standard OpenWrt package in `package/network/services/boringtun-rust/`:
  - Builds from Cloudflare BoringTun source with our patches 0001 and 0002.
  - Statically linked via `cargo build --target aarch64-unknown-linux-musl --release`.
  - Installs `/usr/bin/boringtun-cli` (1.18 MB stripped) and procd init service `/etc/init.d/wireguard_boringtun`.
- Integrates `cr8818-watchdog` and `cr8818-telemetry` microservices.

---

## 4. Repository Synchronization & Rebase Workflow

To maintain clean traceability and enable continuous updates from upstream without merge conflicts:

```
                      +-----------------------------+
                      |   Official OpenWrt / LTS    |
                      +-----------------------------+
                                     |
                                     v (Periodic Git Fetch / Rebase)
+--------------------+   +-----------------------------+   +--------------------+
| yangfl CR8818 DTS  | ->| CR8808-CUSTOM-FIRMWARE      |<- | zcop YT9215 Regmap |
| & SerDes Patch 940 |   | Integration Branch          |   | & Enhanced Tagger  |
+--------------------+   +-----------------------------+   +--------------------+
                                     |
                                     v (Automated CI / Local Kbuild)
                      +-----------------------------+
                      | Verified Firmware Artifacts |
                      | (factory.ubi / sysupgrade)  |
                      +-----------------------------+
```

### Git Rebase & Synchronization Rules:
1. **Zero Direct Edits on Upstream Files:** Upstream OpenWrt core files are NEVER modified directly. All alterations exist exclusively as numbered patch files in `patches/` or target board directories.
2. **Patch Provenance Header:** Every patch file must contain a standardized header specifying:
   - Upstream author & email.
   - Upstream commit SHA or bug reference.
   - Target kernel/package version.
   - Clear technical explanation of the fix.
3. **Automated Source Lock:** All external dependencies are pinned by exact 40-character commit SHAs in `manifests/m7-sources.lock.yaml`. Build scripts reject dirty checkouts or floating branch heads.
