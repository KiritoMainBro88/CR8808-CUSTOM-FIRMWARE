#!/bin/sh
# tests/test_sanitizer.sh
# Empirical Test Harness for Multi-Layer Redaction Sanitizer
# Validates scrubbing of MACs, SSIDs, Wi-Fi Keys, Serials, Public/WAN IPv4,
# IPv6 Global/Link-Local/ULA, and WireGuard Keys across multiline text and JSON.

set -e

TMP_DIR="$(mktemp -d /tmp/m11_sanitizer_test.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SANITIZER="scripts/sanitize_telemetry.sh"
FIXTURE_TXT="tests/fixtures/sanitizer_test_multiline.txt"
FIXTURE_JSON="tests/fixtures/sanitizer_test_json.json"

OUT_TXT="${TMP_DIR}/sanitized_txt.txt"
OUT_JSON="${TMP_DIR}/sanitized_json.txt"

echo "=== M11.1.0.2 SANITIZER COMPREHENSIVE TEST SUITE ==="

# Execute Sanitization on both fixtures
sh "$SANITIZER" < "$FIXTURE_TXT" > "$OUT_TXT"
sh "$SANITIZER" < "$FIXTURE_JSON" > "$OUT_JSON"

# Assertion helper: verifies pattern is ABSENT
assert_absent() {
    FILE="$1"
    PATTERN="$2"
    LABEL="$3"
    if grep -iq "$PATTERN" "$FILE"; then
        echo "FAIL: Sensitive pattern leaked: $LABEL ('$PATTERN') in $FILE"
        exit 1
    else
        echo "PASS: Scrubbed $LABEL."
    fi
}

# Assertion helper: verifies redaction token is PRESENT
assert_present() {
    FILE="$1"
    TOKEN="$2"
    LABEL="$3"
    if grep -q "$TOKEN" "$FILE"; then
        echo "PASS: Redaction token present: $LABEL ($TOKEN)."
    else
        echo "FAIL: Expected redaction token missing: $LABEL in $FILE"
        exit 1
    fi
}

echo "--- [PHASE 1] Validating Multiline Text Sanitization ---"
assert_absent "$OUT_TXT" "35123/240019283" "Serial Number"
assert_absent "$OUT_TXT" "E4:39:DF:04:6C:FD" "MAC Address (Colon uppercase)"
assert_absent "$OUT_TXT" "E4-39-DF-04-6C-FE" "MAC Address (Hyphen uppercase)"
assert_absent "$OUT_TXT" "Xiaomi_8808_5G_Home" "Wi-Fi SSID"
assert_absent "$OUT_TXT" "SuperSecretWifiPass123!" "Wi-Fi WPA2 Password"
assert_absent "$OUT_TXT" "WPA3SecretPassWord999" "Wi-Fi WPA3 Password"
assert_absent "$OUT_TXT" "192.168.100.75" "WAN IPv4 Subnet"
assert_absent "$OUT_TXT" "118.68.195.158" "Public IPv4"
assert_absent "$OUT_TXT" "2402:800:63a5:4432" "IPv6 Global Unicast"
assert_absent "$OUT_TXT" "fe80::e639" "IPv6 Link-Local"
assert_absent "$OUT_TXT" "fd00:dead:beef" "IPv6 ULA"
assert_absent "$OUT_TXT" "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY=" "WireGuard Server Key"
assert_absent "$OUT_TXT" "MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI=" "WireGuard Client Key"

assert_present "$OUT_TXT" "REDACTED_SERIAL" "Serial Token"
assert_present "$OUT_TXT" "REDACTED_MAC" "MAC Token"
assert_present "$OUT_TXT" "REDACTED_SSID" "SSID Token"
assert_present "$OUT_TXT" "REDACTED_WIFI_KEY" "Wi-Fi Key Token"
assert_present "$OUT_TXT" "REDACTED_WG_KEY" "WireGuard Key Token"
assert_present "$OUT_TXT" "REDACTED_WAN_IP" "WAN IP Token"
assert_present "$OUT_TXT" "REDACTED_PUBLIC_IP" "Public IP Token"
assert_present "$OUT_TXT" "REDACTED_IPV6_GUA" "IPv6 Global Unicast Token"
assert_present "$OUT_TXT" "REDACTED_IPV6_LL" "IPv6 Link-Local Token"
assert_present "$OUT_TXT" "REDACTED_IPV6_ULA" "IPv6 ULA Token"

echo "--- [PHASE 2] Validating JSON Structure Sanitization ---"
assert_absent "$OUT_JSON" "35123/240019283" "JSON Serial"
assert_absent "$OUT_JSON" "CR8818-SN-998877" "JSON SN"
assert_absent "$OUT_JSON" "e4:39:df:04:6c:fd" "JSON MAC"
assert_absent "$OUT_JSON" "e4:39:df:04:6c:fe" "JSON BSSID"
assert_absent "$OUT_JSON" "Xiaomi_8808_Fast" "JSON SSID"
assert_absent "$OUT_JSON" "SuperSecretWifiPass123!" "JSON Wi-Fi Key"
assert_absent "$OUT_JSON" "WPA3SecretPassWord999" "JSON SAE Password"
assert_absent "$OUT_JSON" "192.168.100.75" "JSON WAN IP"
assert_absent "$OUT_JSON" "118.68.195.158" "JSON Public IP"
assert_absent "$OUT_JSON" "2402:800:63a5:4432" "JSON IPv6 Global"
assert_absent "$OUT_JSON" "fe80::e639" "JSON IPv6 Link-Local"
assert_absent "$OUT_JSON" "fd00:dead:beef" "JSON IPv6 ULA"
assert_absent "$OUT_JSON" "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY=" "JSON WG srvkey"
assert_absent "$OUT_JSON" "MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI=" "JSON WG clientkey"
assert_absent "$OUT_JSON" "c29tZXJhbmRvbXdpcmVndWFyZHByaXZhdGVrZXkxMjM0NTY=" "JSON WG private_key"

assert_present "$OUT_JSON" "REDACTED_SERIAL" "JSON Serial Token"
assert_present "$OUT_JSON" "REDACTED_MAC" "JSON MAC Token"
assert_present "$OUT_JSON" "REDACTED_SSID" "JSON SSID Token"
assert_present "$OUT_JSON" "REDACTED_WIFI_KEY" "JSON Wi-Fi Key Token"
assert_present "$OUT_JSON" "REDACTED_WG_KEY" "JSON WG Key Token"
assert_present "$OUT_JSON" "REDACTED_WAN_IP" "JSON WAN IP Token"
assert_present "$OUT_JSON" "REDACTED_PUBLIC_IP" "JSON Public IP Token"

echo "=== ALL SANITIZER ASSERTIONS PASSED (100% CLEAN REDACTION) ==="
