# MILESTONE M11.0.1: SECURITY INCIDENT CONTAINMENT & CREDENTIAL REMEDIATION REPORT

**Document ID:** `CR8808-M11.0.1-INCIDENT-001`  
**Milestone:** `M11.0.1 – Security Incident Containment & Evidence Correction`  
**Severity Level:** **P0 – CRITICAL (Credential Exposure in Public Repository)**  
**Target Hardware:** Xiaomi CR8808 Ver.B (Codename `CR8818`, RA82 v1.4.31)  
**Reporting Authority:** Gemini 3.8 Flash High – Lead Developer / Research Engineer  
**Receiving Authority:** ChatGPT – Chief Architect / Architecture Lead  
**Date:** November 11, 2026  
**Git Branch:** `feature/m11-ra82-optimization-audit`  
**Incident Commit:** `3b5349e` (Pushed to GitHub `origin`)

---

## 1. Incident Overview & Discovery

During the execution of Milestone M11 (Passive Read-Only Performance & Security Audit), an automated data collection script (`scripts/m11_ra82_optimization_audit.sh`) dumped raw router state into `reports/M11_RA82_LIVE_AUDIT_RAW.txt`. This file was committed in `3b5349e` and pushed to the public GitHub repository `https://github.com/KiritoMainBro88/CR8808-CUSTOM-FIRMWARE`.

During post-commit architectural audit, Chief Architect (ChatGPT) identified that this file contained active authentication credentials:
1. **Wi-Fi PSK / SAE Passwords:** Output from `uci show wireless` at lines 759, 791, and 800 contained cleartext WPA2 pre-shared keys and WPA3 SAE passwords.
2. **WireGuard Server Private Key:** Output from `ps w` at lines 329 and 1096 contained cleartext command-line arguments passed to `/data/wg_server` (`-srvkey <base64_private_key>` and `-clientkey <base64_client_key>`).

---

## 2. Risk Assessment & Threat Modeling

```
+----------------------------------------------------------------------------------------------------+
|                                    CREDENTIAL EXPOSURE IMPACT MATRIX                               |
+--------------------+-----------------------------+----------------------+--------------------------+
| Credential Exposed | Scope of Impact             | Exposure Vector      | Risk Level & Threat      |
+--------------------+-----------------------------+----------------------+--------------------------+
| Wi-Fi WPA2/WPA3    | Local Wireless LAN          | Public GitHub Commit | **HIGH (Local Proximity)**|
| Passwords          | (2.4G / 5G [REDACTED_SSID]) |                      | Unauthorized Wi-Fi access|
|                    |                             |                      | if attacker in RF range. |
+--------------------+-----------------------------+----------------------+--------------------------+
| WireGuard Server   | Remote VPN Tunnel           | Public GitHub Commit | **CRITICAL (Cryptographic)**|
| Private Key        | (Server `10.99.0.1`, Port   |                      | Complete compromise of   |
|                    | 51820 UDP)                  |                      | VPN confidentiality and  |
|                    |                             |                      | tunnel traffic integrity.|
+--------------------+-----------------------------+----------------------+--------------------------+
```

---

## 3. Immediate Containment Actions Executed

In strict compliance with Chief Architect directives, the following containment actions were applied immediately:

### 3.1 Working Tree Sanitization (Immediate)
- All instances of authentication credentials in `reports/M11_RA82_LIVE_AUDIT_RAW.txt` were scrubbed and replaced with deterministic redaction placeholders:
  - `-srvkey [REDACTED_WG_PRIVATE_KEY]`
  - `-clientkey [REDACTED_WG_CLIENT_KEY]`
  - `wireless.@wifi-iface[0].key='[REDACTED_WIFI_KEY]'`
  - `wireless.@wifi-iface[1].key='[REDACTED_WIFI_KEY]'`
  - `wireless.@wifi-iface[1].sae_password='[REDACTED_WIFI_KEY]'`
- Verified via `git grep` that **zero occurrences** of the compromised key strings remain in the working directory.

### 3.2 Git Pre-Commit Ingestion Blocker (`.gitignore`)
Updated `.gitignore` to permanently exclude any un-sanitized raw telemetry files from future tracking:
```gitignore
# Raw audit logs containing live router state
*LIVE_AUDIT_RAW*.txt
*live_device_audit*.txt
*raw_host_audit*.json
*raw_audit*
*.auth
*.credentials
```

### 3.3 Audit Script Hardening (`scripts/m11_ra82_optimization_audit.sh`)
The audit script has been completely re-architected with defensive controls:
1. **No Command-Line Password Passing:** Replaced `sshpass -p "$ROUTER_PASS"` with `export SSHPASS; sshpass -e`, eliminating exposure in workstation process listing (`ps aux`).
2. **Host Key Verification:** Replaced `-o StrictHostKeyChecking=no` with a dedicated `ssh-keyscan` to a temporary known_hosts file, preventing Man-in-the-Middle (MitM) spoofing.
3. **Automated Dual-Layer Redaction:** Added `sed` pattern filters both within the remote SSH subshell and on the local output pipe before file write, ensuring credentials NEVER touch disk in cleartext.

---

## 4. Mandatory User Security Advisory

> [!CAUTION]
> ### URGENT ACTION REQUIRED BY DEVICE OWNER
> Because commit `3b5349e` was pushed to GitHub, the exposed credentials must be considered **FULLY COMPROMISED**. The device owner must execute the following remediation steps immediately:
> 
> 1. **Rotate Wi-Fi Passwords:**  
>    Log in to the router web management interface (`http://192.168.31.1`) or via SSH and change the Wi-Fi passwords for both 2.4 GHz and 5 GHz networks immediately.
> 
> 2. **Rotate WireGuard Key Material:**  
>    - Generate a brand-new WireGuard private key and preshared key pair:
>      ```sh
>      wg genkey | tee new_server_private.key | wg pubkey > new_server_public.key
>      wg genpsk > new_preshared.key
>      ```
>    - Update `/data/wg_server` execution parameters with the new keys.
>    - Revoke all existing peer configurations on client devices (phones, laptops) and issue new client configuration profiles.

---

## 5. Git History Remediation Plan

Per Chief Architect instructions: **DO NOT force-push or rewrite public history without explicit owner approval.**

Below is the certified, non-destructive step-by-step remediation procedure prepared for the repository owner to purge commit `3b5349e` history when authorized:

### Option A: Clean History Rewrite via `git-filter-repo` (Recommended)
```bash
# 1. Install git-filter-repo (Python 3 tool)
pip install git-filter-repo

# 2. Create replacements file (Insert the exposed strings locally on your secure machine; DO NOT commit literal secrets)
cat << 'EOF' > /tmp/credential_replacements.txt
<EXPOSED_WIFI_PASSPHRASE>==>[REDACTED_WIFI_KEY]
<EXPOSED_WG_SERVER_PRIVATE_KEY>==>[REDACTED_WG_PRIVATE_KEY]
<EXPOSED_WG_CLIENT_PUBLIC_KEY>==>[REDACTED_WG_CLIENT_KEY]
EOF

# 3. Execute dry-run / filter
git filter-repo --replace-text /tmp/credential_replacements.txt

# 4. Verify clean history and force-push to remotes upon approval:
# git push origin --force --all
```

### Option B: Squashed Integration (Conservative)
When branch `feature/m11-ra82-optimization-audit` is eventually merged into `develop` or `main`, it must be merged strictly using **Squash & Merge** (`git merge --squash`) with a sanitized single commit message, ensuring the intermediate commit `3b5349e` is never propagated into the primary project branches.

---

## 6. Incident Status & Next Actions

- **Containment Status:** **CONTAINED IN WORKING TREE & SCRIPT PIPELINE.**
- **Artifacts:** Raw log `reports/M11_RA82_LIVE_AUDIT_RAW.txt` has been removed from Git `HEAD` (`git rm`) under M12.6 P0-1 remediation; sanitized baseline telemetry is maintained in `reports/M12_BASELINE_SANITIZED.txt` and `reports/M12_6_LIVE_SANITIZED.txt`.
- **Git History Rewrite:** **PENDING REPOSITORY OWNER WRITTEN AUTHORIZATION.**
