# Security Lifecycle & Continuous Upstream Synchronization Strategy (M7.0)

- **Document ID:** `docs/M7/SECURITY_AND_UPDATE_STRATEGY.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018, 256MB RAM, 128MB SPI NAND)
- **Author:** Gemini 3.8 Flash High (Lead Developer / Research Engineer)
- **Reporting Authority:** ChatGPT (Chief Architect / Architecture Lead)
- **Status:** Complete Security Engineering Specification for Gate M7.0

---

## 1. Executive Summary & Security Philosophy

The Chief Architect's directive mandates:
> *"Chiến lược cập nhật kernel, package, firmware. CVE monitoring. Upstream synchronization. Không được hy sinh khả năng hoạt động của phần cứng chỉ để chạy kernel mới hơn. Đảm bảo phần mềm mới, bảo mật được cập nhật thường xuyên, nhưng không đánh mất hiệu năng và khả năng điều khiển phần cứng."*

Security in an embedded routing appliance is not a one-time build attribute; it is an active operational process. This document establishes the security architecture, automated CVE monitoring pipeline, upstream rebase mechanics, and cryptographically verified update lifecycle for the CR8808 Ver.B custom firmware.

---

## 2. Supply Chain Governance & Build Reproducibility

### 2.1 Cryptographic Pinning & Source Locks
All source code, toolchains, package feeds, and patches are anchored by exact cryptographic hashes:
- Maintained centrally in `manifests/m7-sources.lock.yaml`.
- Pinned to 40-character Git commit SHAs (no floating branch heads or ambiguous tags).
- Downstream build pipelines abort immediately if any fetched tarball or git object fails SHA-256 verification.

### 2.2 Deterministic & Reproducible Builds
To prevent compiler backdoors or host environment leakage:
1. **`SOURCE_DATE_EPOCH` Clamping:** Timestamps in compiled binaries, squashfs root filesystems, and gzip headers are clamped to the exact UNIX timestamp of the latest git commit:
   ```bash
   export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
   ```
2. **Path Sanitization:** C and Rust compilers execute with `-ffile-prefix-map` and `--remap-path-prefix` to strip developer host directory paths from compiled binaries.
3. **Hermetic Compilation Environment:** Target binaries are cross-compiled using locked musl toolchains with `-C target-feature=+crt-static`, eliminating host dynamic library variance.

### 2.3 Software Bill of Materials (SBOM) Generation
Every firmware build automatically emits a full machine-readable SBOM in **SPDX 2.3 JSON** format (`artifacts/m6_build/sbom.spdx.json`):
- Indexes all 71 kernel modules, C libraries, OpenWrt packages, and Rust crates.
- Contains exact version identifiers, package checksums, and SPDX license tags.
- Verified in Milestone M6 (SHA-256: `915dc15740fcff537b0d77c442461ba0882e3c04907a97ae89d1512c1ebddf62`).

---

## 3. Vulnerability Management & CVE Monitoring Pipeline

The firmware incorporates three automated vulnerability scanning layers:

```
+-----------------------------------------------------------------------------------------------+
|                                AUTOMATED VULNERABILITY AUDITING                               |
+-----------------------------------------------------------------------------------------------+
| Layer 1: Rust Userspace Dependencies                                                          |
| - cargo audit: Scans Cargo.lock against RustSec Advisory Database (crates.io).                |
| - cargo deny: Bans GPLv3 in userspace, enforces single crypto version (ring, chacha20poly1305)|
+-----------------------------------------------------------------------------------------------+
| Layer 2: OpenWrt Packages & Userspace Daemons                                                 |
| - apk-tools v3 security audit: Scans installed packages against OpenWrt Security Advisories.  |
| - Automated Trivy / Grype scanner ingestion of sbom.spdx.json.                                |
+-----------------------------------------------------------------------------------------------+
| Layer 3: Linux Kernel & Out-of-Tree Drivers                                                   |
| - Kernel CVE tracker: Tracks stable Linux 6.12.y / 6.18.y patches from Greg Kroah-Hartman.    |
| - Static Analysis: sparse, clang-tidy, and Snyk code scans on custom YT9215 and NSS patches.  |
+-----------------------------------------------------------------------------------------------+
```

### Response Service Level Objectives (SLOs):
- **Critical CVE (CVSS $\ge$ 9.0, Remote Unauthenticated):** Point-release patch within 72 hours.
- **High CVE (CVSS 7.0 - 8.9):** Patch incorporated in next bi-weekly maintenance release.
- **Medium / Low CVE:** Evaluated and bundled in scheduled milestone updates.

---

## 4. Upstream Synchronization & Patch Maintenance Workflow

To avoid falling into the "frozen vendor fork" trap (which left stock RA82 stranded on Linux 4.4 for 6+ years), the custom firmware employs a structured rebase workflow:

### 4.1 Upstream Tracking Rhythm
- **Track A (Daily Driver - OpenWrt 25.12 LTS):**
  - Synchronizes with official `openwrt/openwrt` `openwrt-25.12` branch monthly.
  - Receives Linux kernel 6.12 point releases (e.g. 6.12.112 $\rightarrow$ 6.12.113) automatically via OpenWrt kernel bumps.
- **Track B (Next-Gen - Linux 6.18 LTS):**
  - Synchronizes with `kuncy7/openwrt-nss-edma` and mainline Linux 6.18 branch quarterly.
  - Re-evaluates NSS glue layer (`kmod-qca-dwmac-nss`) against kernel internal API changes.

### 4.2 Patch Management Protocol
All board-specific modifications exist as discrete, numbered patches:
1. `patches/kernel/`:
   - `940-net-dsa-yt921x-Abuse-SGMII-for-REVSGMII.patch`: Maintained for SerDes role alignment.
   - `967-xx-net-dsa-yt921x-*.patch`: Maintained for YT9215SC switch register handling.
2. When rebasing onto a new OpenWrt release:
   - Run `git rebase --onto <new-tag> <old-tag>`.
   - Test patch application cleanly with `git apply --check`.
   - If upstream merges a backported patch (e.g. David Yang's YT921x patches merged into mainline), retire our local patch file.

---

## 5. Hardened Default Security Configuration

The firmware enforces zero-trust default configurations out of the box:

```
               INTERNET / UNTRUSTED WAN
                           |
            [ Strict nftables DROP Policy ]
                           |
           +---------------+---------------+
           |                               |
     WAN Web UI (uhttpd)             WAN SSH (Dropbear)
     STRICTLY BLOCKED                STRICTLY BLOCKED
     (0 open WAN ports)              (0 open WAN ports)
                           |
                           v
        [ WireGuard VPN Tunnel / BoringTun ]
        - Public-key authentication only
        - ChaCha20-Poly1305 encryption
        - Immune to Issue #498 panics
                           |
                           v
            TRUSTED LOCAL NETWORK (LAN)
           +---------------+---------------+
           |                               |
     Local LuCI Web UI               Local SSH Console
     - Forced TLS/HTTPS              - Public key authentication
     - Strict session timeout        - Password auth disabled
     - CSRF token validation         - Accessible only via LAN/VPN
```

---

## 6. Non-Destructive Firmware Update Lifecycle

Firmware updates must never brick the router or erase user configuration:

1. **Dual-Partition UBI Staging:**
   - The device features dual rootfs volumes: `rootfs` (Slot A) and `rootfs_1` (Slot B).
   - During `sysupgrade`, the new firmware image is written strictly to the **inactive partition**.
   - The active partition and user configuration overlay (`/overlay`) remain completely untouched during the write.
2. **Atomic Bootcounter Handoff:**
   - Once the write completes, the bootloader environment variable `flag_boot_rootfs` is toggled.
   - The boot failure counter `flag_boot_failure` is initialized to `3`.
   - On reboot, if the new kernel crashes or panics 3 times before reaching userspace, the U-Boot bootloader automatically inverts `flag_boot_rootfs` and reboots back into the working partition!
