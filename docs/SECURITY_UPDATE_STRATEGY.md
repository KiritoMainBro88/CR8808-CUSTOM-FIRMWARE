# Security Engineering & Continuous Update Strategy

- **Document ID:** `docs/SECURITY_UPDATE_STRATEGY.md`
- **Project:** `CR8808-CUSTOM-FIRMWARE` (v0.2.0-dev)
- **Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, Qualcomm IPQ5018, 256MB RAM, 128MB SPI NAND)
- **Author:** Gemini Engineering Team (Implementer / System Operator)
- **Reviewer:** ChatGPT Architecture Lead & Product Owner
- **Status:** Mandatory Security Architecture Specification

---

## 1. Core Security Philosophy & Hard Realities

> [!IMPORTANT] **Security Principle: Software Freshness vs. Security Maintenance**
> Newer software does not inherently equal more secure software. Newly introduced features frequently introduce regressions, memory corruptions, or configuration vulnerabilities. Real security relies upon:
> 1. Fast, deterministic patching of known Common Vulnerabilities and Exposures (CVEs).
> 2. An audited, reproducible supply chain with zero unpinned dependencies.
> 3. A hardened, defensive default posture that minimizes attack surface.
> 4. Failsafe configuration rollback that prevents bricking during emergency updates.

Stock Xiaomi RA82 firmware runs a legacy Linux 4.4.60 kernel and embedded daemons dating back to 2018-2021. Multiple publicly known vulnerabilities in `dnsmasq`, `uhttpd`, and the network stack remain unpatched in vendor code. Our custom firmware addresses this through continuous upstream synchronization, reproducible builds, and strict supply chain governance.

---

## 2. Supply Chain Governance & Build Reproducibility

### 2.1 Pinned Source Revisions & Manifest Verification
- All upstream source repositories, submodules, kernel patches, and tarballs must be pinned to exact commit SHAs or release tarball cryptographic hashes.
- Governed centrally via [`manifests/sources.yaml`](../manifests/sources.yaml):
  - BoringTun: Git tag `boringtun-cli-0.7.1` (Commit `253f7afb2b3df9e952065d10bf2af19913cb176b`), Tarball SHA256 `0bfce9717e898533036c853e3433308770d9cd0a5f54b10e9d90f149947e355c`.
  - OpenWrt Base: Pinned tag `v25.12.6` (Git commit hash verified).
  - Qualcomm NSS Modules: Git tags pinned to verified IPQ50xx commits in `kuncy7` / `qca` trees.
- Builds verify hash matching prior to unpacking; any mismatch aborts the build pipeline immediately.

### 2.2 Reproducible Builds Standard
To guarantee that firmware binaries cannot be surreptitiously tampered with or influenced by the host environment:
1. **`SOURCE_DATE_EPOCH` Enforced:** All build timestamps in binaries, gzip archives, and squashfs root filesystems are clamped to a deterministic epoch:
   ```bash
   export SOURCE_DATE_EPOCH=$(git log -1 --format=%ct)
   ```
2. **Hermetic Host Environment:** Builds execute within isolated containerized toolchains (Debian/Ubuntu LTS musl cross-environment) with fixed paths and sanitized `PATH`, `LANG=C`, and `LC_ALL=C`.
3. **Compiler Determinism:** Rust and C compilers execute with `-C codegen-units=1`, `-C debuginfo=0`, and `-ffile-prefix-map` to strip host system filesystem paths from target binaries.

### 2.3 Software Bill of Materials (SBOM) Generation
Every release build automatically generates a standardized SBOM in CycloneDX / SPDX JSON format:
- Comprehensive inventory of all kernel modules, C libraries, OpenWrt packages, and Rust crates.
- Complete version metadata, upstream repository URLs, license identifiers, and SHA256 file hashes.
- Retained in release artifacts alongside images for vulnerability scanner ingestion (`trivy`, `grype`).

---

## 3. Rust & C Dependency Security Auditing

### 3.1 Cargo Dependency Auditing Protocol
Rust userspace binaries (`boringtun-cli`, custom daemons) undergo automated dependency vulnerability auditing before every build:
1. **`cargo audit` Integration:** The `Cargo.lock` file is scanned against the official RustSec Advisory Database.
2. **`cargo deny` Compliance Checks:**
   - License check: Bans GPLv3 / AGPL in proprietary-sensitive userspace, permits MIT, Apache-2.0, BSD-3-Clause.
   - Banned crates: Enforces exclusion of unmaintained crates (e.g. `atty`, `net2`).
   - Duplicate crate detection: Prevents multiple incompatible versions of crypto primitives (`ring`, `x25519-dalek`) in the binary.
3. **Audit Results for BoringTun 0.7.1:**
   - Removal of vulnerable `atty` dependency (RUSTSEC-2021-0145 / CVE-2021-45710) confirmed.
   - 64-bit nonce counter overflow protection on 32-bit platforms confirmed.
   - Zero open critical advisories in pinned `Cargo.lock`.

### 3.2 C & Kernel Patch Auditing
- All kernel patches applied to the clean OpenWrt tree must be reviewed for memory safety (buffer bounds, integer overflows).
- Backported driver patches from vendor QSDK trees (such as Motorcomm YT9215SC switch driver and NSS offload) are audited with static analysis tools (`clang-tidy`, `sparse`) to prevent pointer dereference bugs and race conditions.

---

## 4. Hardened Default Security Posture

A secure firmware must be secure out-of-the-box, without requiring expert manual configuration:

```
               INTERNET / WAN (Untrusted)
                           |
             [ Strict nftables DROP Policy ]
                           |
            +--------------+--------------+
            |                             |
      WAN Web UI (uhttpd)           WAN SSH (Dropbear)
      STRICTLY DISABLED             STRICTLY DISABLED
      (Zero Open Ports)             (Zero Open Ports)
                           |
                           v
        [ WireGuard VPN Tunnel / BoringTun ]
        - Ed25519 / ChaCha20-Poly1305 Only
        - Mandatory Public-Key Authentication
                           |
                           v
             LOCAL AREA NETWORK / LAN (Trusted)
            +--------------+--------------+
            |                             |
     Local LuCI Web UI             Local SSH Console
     - Forced TLS/HTTPS            - Ed25519 Public Key Only
     - Strict Session Timeout      - Password Auth Disabled
     - CSRF Token Protection       - Root Password Enforced
```

### 4.1 WAN Attack Surface Elimination
- **Zero Inbound Ports on WAN:** Default `firewall4` nftables policy is `DROP` for all unsolicited inbound IPv4 and IPv6 traffic.
- **WAN Web UI Access Disabled:** `uhttpd` listens strictly on the internal LAN interface (`192.168.1.1` and `fd00::/64`). Remote WAN management is blocked at both firewall and socket levels.
- **WAN SSH Access Disabled:** Dropbear SSH daemon rejects connections from WAN interfaces.

### 4.2 Hardened Administrative Access
- **SSH Key-Based Authentication:** Public key authentication (`ed25519`) is mandatory. Password authentication over SSH is disabled once an initial key is provisioned.
- **Web UI Session Hardening:** LuCI utilizes HTTPS with modern TLS cipher suites, strict `SameSite=Strict` session cookies, and cross-site request forgery (CSRF) mitigation.
- **No Private Key Leakage in Logs:**
  - `wireguard_boringtun.sh` enforces `umask 077` when writing temporary configuration sockets.
  - Logging daemons redact WireGuard private keys and preshared keys from syslog and `procd` traces.

---

## 5. Security Update Cadence & Patching Protocol

```
+-----------------------------------------------------------------------------+
|                          CVE Tracking & Patch Flow                          |
+-----------------------------------------------------------------------------+
                                      |
       +------------------------------+------------------------------+
       |                                                             |
       v                                                             v
 [ OpenWrt Security Advisories ]                       [ Kernel.org LTS CVE Stream ]
 (uhttpd, dnsmasq, dropbear, etc.)                     (Linux 6.12 / 6.18 Networking)
       |                                                             |
       +------------------------------+------------------------------+
                                      |
                                      v
                 [ Vulnerability Severity Assessment ]
                                      |
            +-------------------------+-------------------------+
            |                                                   |
   CRITICAL / ZERO-DAY                                 ROUTINE / LOW-MEDIUM
   (CVSS >= 8.5 / Active Exploit)                      (CVSS < 8.5)
            |                                                   |
            v                                                   v
   [ 24-48h Emergency Hotfix ]                         [ Monthly Maintenance Release ]
   - Pin patched source commit                         - Synchronize stable branch
   - Hermetic PC compilation                           - Run full test suite
   - Generate signed sysupgrade                        - Tag release vX.Y.Z
```

### 5.1 Emergency Zero-Day Vulnerability Protocol
If an unauthenticated remote code execution (RCE) or denial-of-service vulnerability is disclosed in a core service (`dnsmasq`, `nftables`, `boringtun`, `uhttpd`):
1. **T+0 Hours (Triage):** Assess whether CR8818 default configuration is exposed. If WAN is isolated, priority is adjusted accordingly.
2. **T+12 Hours (Patch Integration):** Cherry-pick security fix from upstream OpenWrt git or vendor repository into the custom repository.
3. **T+24 Hours (Validation):** Recompile image on PC; run network namespace integration tests and verify that the vulnerability is mitigated without regression.
4. **T+48 Hours (Distribution):** Publish signed sysupgrade artifact with SHA256 checksums and CVE resolution disclosure.

### 5.2 Artifact Verification & Signing
- Every published release image is accompanied by a detached signature generated using `signify-openwrt` or GnuPG:
  ```bash
  sha256sum openwrt-ipq50xx-cr8818-sysupgrade.bin > SHA256SUMS
  signify-openwrt -S -s release-key.sec -m SHA256SUMS
  ```
- Before applying any update, the router verifies cryptographic signatures against embedded public keys stored in `/etc/opkg/keys/`.

---

## 6. Failsafe & Configuration Rollback Architecture

To eliminate the risk of a faulty security update rendering the router unbootable ("bricked"):

### 6.1 U-Boot Bootcounter Fallback (`bootcount`)
- The U-Boot bootloader tracks boot attempts via the `bootcount` environment variable stored in SPI NAND.
- During sysupgrade, `bootcount=0` and `upgrade_step=1` are set.
- If the new kernel panics or fails to reach userspace `procd` within 180 seconds, the hardware watchdog triggers a reset.
- Upon reaching `bootlimit=3`, U-Boot automatically reverts the active boot partition to the secondary alternate kernel/rootfs slot (`rootfs_1` -> `rootfs_2`).

### 6.2 OverlayFS Revert & Failsafe Boot
- The root filesystem uses read-only SquashFS for core OS binaries, paired with an OverlayFS partition for writable configurations (`/overlay`).
- If an update corrupts `/etc/config/*`, holding the reset button during boot invokes OpenWrt Failsafe Mode:
  - Boots with default static IP `192.168.1.1`.
  - Disables OverlayFS mounting, allowing administrative recovery via telnet/SSH to execute `firstboot` and restore clean defaults.
