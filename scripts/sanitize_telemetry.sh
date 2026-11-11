#!/bin/sh
# scripts/sanitize_telemetry.sh
# Multi-Layer Stream Sanitizer for Router Telemetry & Logs
# Scrubbing sensitive identifiers: MAC, BSSID, SSID, PSK, Serial,
# WireGuard Keys, Public/WAN IPv4, and IPv6.
#
# Usage:
#   cat raw_log.txt | sh scripts/sanitize_telemetry.sh > sanitized_log.txt
#   sh scripts/sanitize_telemetry.sh < raw_log.txt > sanitized_log.txt

sed -E \
  -e 's/(-srvkey|-clientkey)[ =]+[A-Za-z0-9+/=]{20,}/-srvkey [REDACTED_WG_KEY]/g' \
  -e 's/(private-key|preshared-key)[ =]+[A-Za-z0-9+/=]{20,}/\1 [REDACTED_WG_KEY]/g' \
  -e 's/"(srvkey|clientkey|private_key|preshared_key)": "[^"]*"/"\1": "[REDACTED_WG_KEY]"/g' \
  -e 's/(key|sae_password|password|passphrase)=['\''"][^'\''"]*['\''"]/\1='\''[REDACTED_WIFI_KEY]'\''/g' \
  -e 's/"(key|sae_password|password|passphrase)": "[^"]*"/"\1": "[REDACTED_WIFI_KEY]"/g' \
  -e 's/ESSID:"[^"]*"/ESSID:"[REDACTED_SSID]"/g' \
  -e 's/ssid=['\''"][^'\''"]*['\''"]/ssid='\''[REDACTED_SSID]'\''/g' \
  -e 's/"(ssid|ESSID)": "[^"]*"/"\1": "[REDACTED_SSID]"/g' \
  -e 's/Serial[ \t]*:[ \t]*[0-9a-zA-Z\/_-]+/Serial\t\t: [REDACTED_SERIAL]/g' \
  -e 's/"(serial|sn|device_sn)": "[^"]*"/"\1": "[REDACTED_SERIAL]"/g' \
  -e 's/([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})/[REDACTED_MAC]/g' \
  -e 's/192\.168\.100\.[0-9]+/[REDACTED_WAN_IP]/g' \
  -e 's/118\.68\.[0-9]+\.[0-9]+/[REDACTED_PUBLIC_IP]/g' \
  -e 's/2[0-9a-fA-F]{3}:([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{1,4}/[REDACTED_IPV6_GUA]/g' \
  -e 's/fe80:([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{1,4}/[REDACTED_IPV6_LL]/g' \
  -e 's/fd[0-9a-fA-F]{2}:([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{1,4}/[REDACTED_IPV6_ULA]/g'
