#!/bin/sh
# tests/test_sanitizer.sh
# Empirical Test Harness for Generalized Multi-Layer Redaction Sanitizer
# Validates scrubbing of MACs, SSIDs, Wi-Fi Keys, Serials, WireGuard Keys,
# Generalized Public/WAN IPv4, IPv6 (GUA 2xxx/3xxx, ULA fcxx/fdxx, Link-Local fe80-febf),
# Compressed/Expanded IPv6, and Hexadecimal addresses in /proc/net/tcp & /proc/net/tcp6.

set -e

TMP_DIR="$(mktemp -d /tmp/m11_sanitizer_test.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SANITIZER="scripts/sanitize_telemetry.sh"
FIXTURE_TXT="tests/fixtures/sanitizer_test_multiline.txt"
FIXTURE_JSON="tests/fixtures/sanitizer_test_json.json"

OUT_TXT="${TMP_DIR}/sanitized_txt.txt"
OUT_JSON="${TMP_DIR}/sanitized_json.txt"

echo "=== M11.1.0.4 GENERALIZED SANITIZER TEST SUITE ==="

# Execute Sanitization
sh "$SANITIZER" < "$FIXTURE_TXT" > "$OUT_TXT"
sh "$SANITIZER" < "$FIXTURE_JSON" > "$OUT_JSON"

# Assertion counter
ASSERTIONS_PASSED=0

assert_absent() {
    FILE="$1"
    PATTERN="$2"
    LABEL="$3"
    if grep -iq "$PATTERN" "$FILE"; then
        echo "FAIL: Sensitive pattern leaked: $LABEL ('$PATTERN') in $FILE"
        exit 1
    else
        echo "PASS: Scrubbed $LABEL."
        ASSERTIONS_PASSED=$((ASSERTIONS_PASSED + 1))
    fi
}

assert_present() {
    FILE="$1"
    TOKEN="$2"
    LABEL="$3"
    if grep -q "$TOKEN" "$FILE"; then
        echo "PASS: Token present: $LABEL ($TOKEN)."
        ASSERTIONS_PASSED=$((ASSERTIONS_PASSED + 1))
    else
        echo "FAIL: Expected token missing: $LABEL in $FILE"
        exit 1
    fi
}

echo "--- [PHASE 1] Multiline Text Sanitization Assertions ---"
assert_absent "$OUT_TXT" "35123/240019283" "Serial Number"
assert_absent "$OUT_TXT" "E4:39:DF:04:6C:FD" "MAC Address (Colon)"
assert_absent "$OUT_TXT" "E4-39-DF-04-6C-FE" "MAC Address (Hyphen)"
assert_absent "$OUT_TXT" "Xiaomi_8808_5G_Home" "Wi-Fi SSID"
assert_absent "$OUT_TXT" "SuperSecretWifiPass123!" "Wi-Fi WPA2 Key"
assert_absent "$OUT_TXT" "WPA3SecretPassWord999" "Wi-Fi WPA3 Key"
assert_absent "$OUT_TXT" "192.168.100.75" "WAN Subnet IP"
assert_absent "$OUT_TXT" "8.8.8.8" "Public IPv4 (Google DNS)"
assert_absent "$OUT_TXT" "1.1.1.1" "Public IPv4 (Cloudflare DNS)"
assert_absent "$OUT_TXT" "45.33.32.156" "Public IPv4 (Linode Subnet)"
assert_absent "$OUT_TXT" "172.217.16.206" "Public IPv4 (Google Edge)"
assert_absent "$OUT_TXT" "203.0.113.195" "Public IPv4 (TEST-NET-3)"
assert_absent "$OUT_TXT" "2402:800:63a5:4432" "IPv6 GUA (2xxx prefix)"
assert_absent "$OUT_TXT" "3ffe:1200:2001:1" "IPv6 GUA (3xxx prefix expanded)"
assert_absent "$OUT_TXT" "3ffe::1" "IPv6 GUA (3xxx prefix compressed)"
assert_absent "$OUT_TXT" "2001:db8::" "IPv6 GUA (trailing ::)"
assert_absent "$OUT_TXT" "2001:db8::/32" "IPv6 GUA (CIDR /32)"
assert_absent "$OUT_TXT" "fc00:1234:5678:9abc" "IPv6 ULA (fc00 prefix)"
assert_absent "$OUT_TXT" "fd00:dead:beef" "IPv6 ULA (fd00 prefix)"
assert_absent "$OUT_TXT" "fc00::" "IPv6 ULA (fc00 trailing ::)"
assert_absent "$OUT_TXT" "fd00::" "IPv6 ULA (fd00 trailing ::)"
assert_absent "$OUT_TXT" "fe80::e639" "IPv6 Link-Local (fe80 prefix)"
assert_absent "$OUT_TXT" "fe90::1234" "IPv6 Link-Local (fe90 prefix)"
assert_absent "$OUT_TXT" "fe80::" "IPv6 Link-Local (trailing ::)"
assert_absent "$OUT_TXT" "fe80::/64" "IPv6 Link-Local (CIDR /64)"
assert_absent "$OUT_TXT" "fe80::1%eth0" "IPv6 Link-Local (Zone ID %eth0)"
assert_absent "$OUT_TXT" "2402080063A54432E639DFFFE046CFD0" "/proc/net/tcp6 Hex IPv6 Address"
assert_absent "$OUT_TXT" "4B64A8C0" "/proc/net/tcp Hex WAN IPv4 Address"
assert_absent "$OUT_TXT" "0164A8C0" "/proc/net/tcp Hex Remote IPv4 Address"
assert_absent "$OUT_TXT" "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY=" "WireGuard Server Key"
assert_absent "$OUT_TXT" "MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI=" "WireGuard Client Key"

assert_present "$OUT_TXT" "REDACTED_SERIAL" "Serial Token"
assert_present "$OUT_TXT" "REDACTED_MAC" "MAC Token"
assert_present "$OUT_TXT" "REDACTED_SSID" "SSID Token"
assert_present "$OUT_TXT" "REDACTED_WIFI_KEY" "Wi-Fi Key Token"
assert_present "$OUT_TXT" "REDACTED_WG_KEY" "WireGuard Key Token"
assert_present "$OUT_TXT" "REDACTED_WAN_IP" "WAN IP Token"
assert_present "$OUT_TXT" "REDACTED_PUBLIC_IP" "Public IP Token"
assert_present "$OUT_TXT" "REDACTED_IPV6_GUA" "IPv6 GUA Token"
assert_present "$OUT_TXT" "REDACTED_IPV6_ULA" "IPv6 ULA Token"
assert_present "$OUT_TXT" "REDACTED_IPV6_LL" "IPv6 Link-Local Token"
assert_present "$OUT_TXT" "REDACTED_HEX_IPV6" "Hex IPv6 Token"
assert_present "$OUT_TXT" "REDACTED_HEX_IPV4" "Hex IPv4 Token"

# Verify that standard local router LAN is preserved
assert_present "$OUT_TXT" "011FA8C0:0035" "Local LAN dnsmasq hex socket (192.168.31.1:53)"

# Verify exact fidelity of netmask preservation (no mutation to .0)
assert_present "$OUT_TXT" "255.255.255.255" "Preserved Netmask Host (255.255.255.255)"
assert_present "$OUT_TXT" "255.255.255.128" "Preserved Netmask Subnet (255.255.255.128)"
assert_present "$OUT_TXT" "255.255.255.0" "Preserved Netmask Class C (255.255.255.0)"

echo "--- [PHASE 2] JSON Structure Sanitization Assertions ---"
assert_absent "$OUT_JSON" "35123/240019283" "JSON Serial"
assert_absent "$OUT_JSON" "CR8818-SN-998877" "JSON SN"
assert_absent "$OUT_JSON" "e4:39:df:04:6c:fd" "JSON MAC"
assert_absent "$OUT_JSON" "e4:39:df:04:6c:fe" "JSON BSSID"
assert_absent "$OUT_JSON" "Xiaomi_8808_Fast" "JSON SSID"
assert_absent "$OUT_JSON" "SuperSecretWifiPass123!" "JSON Wi-Fi Key"
assert_absent "$OUT_JSON" "WPA3SecretPassWord999" "JSON SAE Password"
assert_absent "$OUT_JSON" "192.168.100.75" "JSON WAN IP"
assert_absent "$OUT_JSON" "192.168.100.1" "JSON WAN Gateway"
assert_absent "$OUT_JSON" "8.8.8.8" "JSON Public DNS 1"
assert_absent "$OUT_JSON" "1.1.1.1" "JSON Public DNS 2"
assert_absent "$OUT_JSON" "45.33.32.156" "JSON Server IP 1"
assert_absent "$OUT_JSON" "172.217.16.206" "JSON Server IP 2"
assert_absent "$OUT_JSON" "2402:800:63a5:4432" "JSON IPv6 GUA 2xxx"
assert_absent "$OUT_JSON" "3ffe:1200:2001:1" "JSON IPv6 GUA 3xxx"
assert_absent "$OUT_JSON" "2001:db8::" "JSON IPv6 GUA db8"
assert_absent "$OUT_JSON" "2001:db8::/32" "JSON IPv6 GUA CIDR"
assert_absent "$OUT_JSON" "fc00:1234:5678" "JSON IPv6 ULA fc"
assert_absent "$OUT_JSON" "fd00:dead:beef" "JSON IPv6 ULA fd"
assert_absent "$OUT_JSON" "fc00::" "JSON IPv6 ULA short fc"
assert_absent "$OUT_JSON" "fd00::" "JSON IPv6 ULA short fd"
assert_absent "$OUT_JSON" "fe80::e639" "JSON IPv6 LL fe80"
assert_absent "$OUT_JSON" "fe90::1234" "JSON IPv6 LL fe90"
assert_absent "$OUT_JSON" "fe80::" "JSON IPv6 LL short"
assert_absent "$OUT_JSON" "fe80::/64" "JSON IPv6 LL CIDR"
assert_absent "$OUT_JSON" "fe80::1%eth0" "JSON IPv6 LL zone"
assert_absent "$OUT_JSON" "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY=" "JSON WG srvkey"
assert_absent "$OUT_JSON" "MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI=" "JSON WG clientkey"
assert_absent "$OUT_JSON" "c29tZXJhbmRvbXdpcmVndWFyZHByaXZhdGVrZXkxMjM0NTY=" "JSON WG private_key"

# Verify exact fidelity of netmask preservation in JSON
assert_present "$OUT_JSON" "255.255.255.255" "JSON Preserved Netmask Host"
assert_present "$OUT_JSON" "255.255.255.128" "JSON Preserved Netmask Subnet"
assert_present "$OUT_JSON" "255.255.255.0" "JSON Preserved Netmask Class C"

echo "=== ALL $ASSERTIONS_PASSED SANITIZER ASSERTIONS PASSED ==="
