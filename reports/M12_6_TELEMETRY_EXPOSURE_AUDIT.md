# Milestone M12.6 P0-1: Telemetry Exposure Audit & History Remediation Plan

- **Document ID:** `reports/M12_6_TELEMETRY_EXPOSURE_AUDIT.md`
- **Repository:** `CR8808-CUSTOM-FIRMWARE` (Branch: `feature/m12-ra82-performance-modernization`)
- **Audit Scope:** All 851 unique Git blobs across `git rev-list --all`, working tree UTF-8 and UTF-16LE files, and untracked disk artifacts
- **Policy Constraint:** Public Git history MUST NOT be rewritten or force-pushed without explicit repository owner authorization

---

## 1. Executive Summary of Exposure Findings

During M12.6 Blocker Closure auditing, scanning both UTF-8 and UTF-16LE encodings across all tracked files, untracked local files, and historical Git blobs identified the following telemetry and credential exposures:

1. **Plaintext Secrets & Raw Router Config in `HEAD` (`reports/M12_6_LIVE_RAW.txt`, 33,000 B, UTF-16LE):**
   - Introduced in commit `a8e6cfd` (`feat(m12.6): ra82 real optimization, upgrade & performance delivery`).
   - Encoded as UTF-16LE (causing UTF-8-only checks to miss it), containing plaintext UCI `/etc/config/wireless` entries (`option key`, `option sae_password`, `option ssid`), 9 MAC addresses (3 unique), upstream ONT IP (`[REDACTED_WAN_GW]`), and ISP DNS resolvers.
2. **Legacy Raw Telemetry Still in `HEAD` (`reports/M11_RA82_LIVE_AUDIT_RAW.txt`, 60,614 B):**
   - Originally committed with plaintext secrets in `3b5349e`, partially redacted in `bf3cd7c` (`blob 085ce2962e`), and left tracked in `HEAD` with 20 unredacted MAC addresses (10 unique) and real WAN/subnet IPs.
3. **Untracked Raw Telemetry Files Inside Repository Folder:**
   - `reports/M11_1_R0_LIVE_BASELINE_RAW.txt` and `local_raw_audit/{m11_1_r0_minimal_raw.txt, m12_baseline_raw.txt}` resided inside the repository working directory containing plaintext Wi-Fi credentials, MACs, and WAN IPs.
4. **Sanitizer Pattern Gaps Found in `scripts/sanitize_telemetry.sh`:**
   - Previous rules matched `=` assignments (`key='...'`, `ssid='...'`) and `ESSID:"..."`, missing space-delimited UCI `/etc/config/wireless` syntax (`option key '...'`, `option sae_password '...'`, `option ssid '...'`), unquoted `iw dev` indented `ssid <value>` lines, `iwconfig` hex `Encryption key:...` output, and `net.ipv4.tcp_fastopen_key`.
   - As a result, `reports/M12_BASELINE_SANITIZED.txt` (lines 808, 818, 829, 844, 852, 4940) still contained three unquoted SSIDs, two `iwconfig` hex keys, and one `tcp_fastopen_key`.
5. **Real Identifiers Inside Tracked Reports & Diagrams:**
   - Real AP/STA MACs, EUI-64 hex reconstructing a router MAC, WAN RFC1918/ONT IPs, an earlier external WAN IP, ISP DNS resolvers, and SSID strings appeared in multiple historical markdown/SVG reports (`reports/M12_NETWORK_OUTAGE_RCA.md`, `reports/M11_1_1_POST_AUDIT_REMEDIATION_REPORT.md`, `docs/SSH_HOST_VERIFICATION.md`, `reports/M11_0_2_RA82_OPTIMIZATION_REPORT.md`, `reports/M11_RA82_OPTIMIZATION_AUDIT.md`, `reports/M11_0_1_SECURITY_INCIDENT_REPORT.md`, `reports/M12_6_LIVE_BASELINE.md`, `reports/M12_6_REAL_OPTIMIZATION_REPORT.md`, `reports/M12_5_PERFORMANCE_DELIVERY_REPORT.md`, `docs/M11_1_APPROVED_TRIAL_PLAN.md`, `docs/M12_ARCHITECTURE.md`, `docs/RA82_OPTIMIZATION_MATRIX.md`, `reports/LAB_INTEGRITY_AUDIT.md`, `docs/architecture/cr8818_dual_track_architecture.svg`).

---

## 2. Actions Executed in Current `HEAD` (Safe Forward Remediation)

1. **Sanitizer Hardening & Verification (`scripts/sanitize_telemetry.sh`, `tests/test_sanitizer.sh`):**
   - Added rules covering space-delimited UCI `option key` / `option sae_password` / `option ssid`, `iw dev` unquoted `ssid` lines, `iwconfig` hex `Encryption key:...`, and `net.ipv4.tcp_fastopen_key`.
2. **Confidential Raw File Removal & Relocation:**
   - Converted `reports/M12_6_LIVE_RAW.txt` through `scripts/sanitize_telemetry.sh` into UTF-8 `reports/M12_6_LIVE_SANITIZED.txt`.
   - Re-ran the hardened sanitizer over `reports/M12_BASELINE_SANITIZED.txt` (patching only the 6 missed lines).
   - Moved `M12_6_LIVE_RAW.txt`, `M11_RA82_LIVE_AUDIT_RAW.txt`, `M11_1_R0_LIVE_BASELINE_RAW.txt`, and `local_raw_audit/` outside the repository into `D:\vibecode\CR8808-PRIVATE-LOGS\` and removed tracked raw dumps from Git `HEAD` (`git rm`).
   - Updated `scripts/m11_ra82_optimization_audit.sh` default `OUTPUT_FILE` to write to `/tmp/cr8818_m11_ra82_live_audit_sanitized.txt` instead of `reports/`.
3. **`.gitignore` Hardening:**
   - Added `*LIVE_RAW*`, `*_RAW.txt`, `*RAW_AUDIT*`, and `reports/*_RAW*` alongside existing `*LIVE_AUDIT_RAW*`, `*LIVE_BASELINE_RAW*`, and `local_raw_audit/`.
4. **Report & Documentation Scrubbing:**
   - Redacted all exposed MACs, EUI-64 hex identifiers, WAN/ONT/external IPs, ISP DNS resolvers, and SSIDs across tracked reports and diagrams, and updated references from `*_RAW.txt` to sanitized equivalents.
   - Kept synthetic test fixtures (`tests/fixtures/sanitizer_*`, `tests/test_sanitizer.sh`) and isolated `ip netns` overlay tests (`tests/integration/test_boringtun_netns.sh`, `BORINGTUN_INTEGRATION_TEST_REPORT.md`), while migrating mock gateway documentation in `performance/benchmarks/BENCHMARK_MATRIX.md` to RFC 5737 `198.51.100.2`.

---

## 3. Immutable Git History Exposure Inventory

Because Git commits are immutable and no history rewrite or force-push was executed, sensitive blobs remain reachable in historical commits already pushed to `origin` and `backup`:

| Historical Blob / Path | Key Commits | Exposed Material Still in Git History | Status in Current `HEAD` |
| :--- | :--- | :--- | :--- |
| `reports/M12_6_LIVE_RAW.txt` (`blob 8758e4e095`, UTF-16LE) | `a8e6cfd`, `1437e17` | Plaintext Wi-Fi PSK/SAE passwords, SSIDs, 9 MACs, ONT gateway & ISP DNS IPs | Removed (`git rm`); replaced by `M12_6_LIVE_SANITIZED.txt` |
| `reports/M11_RA82_LIVE_AUDIT_RAW.txt` (`blob 35d3497abb`) | `3b5349e` | Plaintext Wi-Fi passwords, WireGuard `-srvkey`/`-clientkey`, 20 MACs, WAN IP | Removed (`git rm`) |
| `reports/M11_RA82_LIVE_AUDIT_RAW.txt` (`blob 085ce2962e`) | `bf3cd7c` .. `1437e17` | 20 unredacted MACs, WAN IP (`192.168.100.x`), internal/WG subnets | Removed (`git rm`) |
| `reports/M12_BASELINE_SANITIZED.txt` (`blob 0c691cb705`) | `8a1dd61` .. `1437e17` | 3 SSIDs (`iw dev`), 2 `iwconfig` hex keys, 1 `tcp_fastopen_key` | Sanitized in `HEAD` |
| `reports/M12_NETWORK_OUTAGE_RCA.md` (`blob 4a7ca64909`, `2e3b13ce65`) | `8f685a2`, `d73eb76` .. `1437e17` | AP BSSID & STA MAC, ISP DNS IPs, gateway IP | Scrubbed in `HEAD` |
| `reports/M11_1_1_POST_AUDIT_REMEDIATION_REPORT.md` (`blob 2b7d77d15d`) & `docs/SSH_HOST_VERIFICATION.md` (`blob 9b6952a724` .. `5265e19a6d`) | `dde2e33`, `cca2e0f`, `677360a` .. `1437e17` | EUI-64 hex/MAC example, WAN subnet IP, historical public WAN IP | Scrubbed in `HEAD` |
| Other historical M11/M12 reports & SVG (`M11_0_1_*`, `M11_0_2_*`, `M11_RA82_*`, `M12_ARCHITECTURE.md`, `M12_5_*`, `M12_6_*`, `LAB_INTEGRITY_AUDIT.md`) | `3b5349e` .. `1437e17` | RFC1918 ONT WAN IP/gateway (`192.168.100.x`), ISP DNS, STA MAC, SSID names | Scrubbed in `HEAD` |

---

## 4. Mandatory Credential Rotation & Optional History Purge Plan

### 4.1 Immediate Owner Actions Required on Router (No History Rewrite Needed)
Because commits `3b5349e`, `a8e6cfd`, and `1437e17` were pushed publicly, assume all exposed secrets are permanently compromised regardless of later history rewrites:
1. **Rotate All Wi-Fi Passwords:** Change WPA2/WPA3 PSK and SAE passwords on both 2.4 GHz (`wl1`) and 5 GHz (`wl0`) radios via Router UI (`http://192.168.31.1`) or UCI.
2. **Rotate WireGuard Keys:** Regenerate server/client keypairs used by `/data/wg_server` (`wg0`) and update all peers.
3. **Harden Router Root Password & Disable WAN SSH Access:** Rotate root/Dropbear password (especially while `PasswordAuth 'on'` / `RootPasswordAuth 'on'` remain enabled) and keep Dropbear restricted from WAN when approved for firewall hardening.
4. **Rotate Pre-Shared/Random Salts if Needed:** Router reboot regenerates `tcp_fastopen_key` and ephemeral keys automatically; re-key Wi-Fi clients after passphrase change.

### 4.2 Repository History Remediation Strategy (Requires Explicit Owner Approval)
- **Default Non-Destructive Path:** Merge finalized branch work into protected release branches via **Squash & Merge** (`git merge --squash`) only after deleting obsolete feature branches containing exposed blobs on `origin` and `backup`.
- **Full History Rewrite Path (Owner-Executed Only, Never Auto-Executed by Agents):**
  1. Wait until branch work is frozen and mirror a fresh bare backup outside Git.
  2. Prepare a local `git-filter-repo` expressions file mapping exposed plaintext passwords, WG keys, MACs, SSIDs, public WAN IP, and ISP DNS strings -> `[REDACTED_*]` tokens (without ever committing that expressions file).
  3. Strip `reports/M12_6_LIVE_RAW.txt` and `reports/M11_RA82_LIVE_AUDIT_RAW.txt` (`--invert-paths --path ...`) and run `--replace-text` across all refs.
  4. Verify zero secret hits on `git rev-list --all`, obtain explicit owner confirmation, and only then execute coordinated `--force` push to `origin` and `backup`, re-cloning all local clones afterward.
