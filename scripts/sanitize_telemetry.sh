#!/bin/sh
# scripts/sanitize_telemetry.sh
# Multi-Layer Stream Sanitizer for Router Telemetry & Audit Logs
# Scrubbing: MACs, BSSIDs, SSIDs, Wi-Fi Keys, Serials, WireGuard Keys,
# Public/WAN IPv4 (generalized), IPv6 (GUA 2000::/3, ULA fc00::/7, Link-Local fe80::/10),
# Compressed/Expanded IPv6, and Hexadecimal addresses in /proc/net/tcp & /proc/net/tcp6.
#
# Usage:
#   sh scripts/sanitize_telemetry.sh < raw_log.txt > sanitized_log.txt

sed -E \
  `# 1. WireGuard Keys (srvkey, clientkey, private-key, preshared-key in CLI and JSON)` \
  -e 's/(-srvkey|-clientkey)[ =]+[A-Za-z0-9+/=]{20,}/-srvkey [REDACTED_WG_KEY]/g' \
  -e 's/(private-key|preshared-key)[ =]+[A-Za-z0-9+/=]{20,}/\1 [REDACTED_WG_KEY]/g' \
  -e 's/"(srvkey|clientkey|private_key|preshared_key)": "[^"]*"/"\1": "[REDACTED_WG_KEY]"/g' \
  \
  `# 2. Wi-Fi Keys & Passwords (WPA2 key, WPA3 sae_password in CLI, UCI, and JSON)` \
  -e 's/(key|sae_password|password|passphrase)=['\''"][^'\''"]*['\''"]/\1='\''[REDACTED_WIFI_KEY]'\''/g' \
  -e 's/"(key|sae_password|password|passphrase)": "[^"]*"/"\1": "[REDACTED_WIFI_KEY]"/g' \
  \
  `# 3. Wireless SSIDs & BSSIDs in CLI, iwconfig, UCI, and JSON` \
  -e 's/ESSID:"[^"]*"/ESSID:"[REDACTED_SSID]"/g' \
  -e 's/ssid=['\''"][^'\''"]*['\''"]/ssid='\''[REDACTED_SSID]'\''/g' \
  -e 's/"(ssid|ESSID)": "[^"]*"/"\1": "[REDACTED_SSID]"/g' \
  \
  `# 4. Serial Numbers in /proc/cpuinfo, U-Boot, and JSON` \
  -e 's/Serial[ \t]*:[ \t]*[0-9a-zA-Z\/_-]+/Serial\t\t: [REDACTED_SERIAL]/g' \
  -e 's/"(serial|sn|device_sn)": "[^"]*"/"\1": "[REDACTED_SERIAL]"/g' \
  \
  `# 5. MAC & BSSID Addresses (colon-separated and hyphen-separated)` \
  -e 's/([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})/[REDACTED_MAC]/g' \
  \
  `# 6. Hexadecimal IPv6 Addresses in /proc/net/tcp6 (32 hex characters followed by :port)` \
  -e 's/\b00000000000000000000000000000000\b/__PRESERVE_HEX6_WILDCARD__/g' \
  -e 's/\b[0-9A-Fa-f]{32}:([0-9A-Fa-f]{4})\b/[REDACTED_HEX_IPV6]:\1/g' \
  -e 's/__PRESERVE_HEX6_WILDCARD__/00000000000000000000000000000000/g' \
  \
  `# 7. Hexadecimal IPv4 Addresses in /proc/net/tcp (8 hex characters)` \
  -e 's/\b00000000:([0-9A-Fa-f]{4})\b/__PRESERVE_HEX4_WILDCARD__:\1/g' \
  -e 's/\b0100007F:([0-9A-Fa-f]{4})\b/__PRESERVE_HEX4_LOOPBACK__:\1/g' \
  -e 's/\b011FA8C0:([0-9A-Fa-f]{4})\b/__PRESERVE_HEX4_LAN__:\1/g' \
  -e 's/\b[0-9A-Fa-f]{8}:([0-9A-Fa-f]{4})\b/[REDACTED_HEX_IPV4]:\1/g' \
  -e 's/__PRESERVE_HEX4_WILDCARD__/00000000/g' \
  -e 's/__PRESERVE_HEX4_LOOPBACK__/0100007F/g' \
  -e 's/__PRESERVE_HEX4_LAN__/011FA8C0/g' \
  \
  `# 8. IPv6 Addresses: GUA (2000::/3: covers 2xxx and 3xxx), ULA (fc00::/7: fcxx and fdxx), Link-Local (fe80::/10: fe80 to febf)` \
  -e 's/\b[23][0-9a-fA-F]{1,3}(:[0-9a-fA-F]{0,4}){2,7}\b/[REDACTED_IPV6_GUA]/g' \
  -e 's/\b[23][0-9a-fA-F]{1,3}::[0-9a-fA-F:]*\b/[REDACTED_IPV6_GUA]/g' \
  -e 's/\bf[cdCD][0-9a-fA-F]{1,3}(:[0-9a-fA-F]{0,4}){2,7}\b/[REDACTED_IPV6_ULA]/g' \
  -e 's/\bf[cdCD][0-9a-fA-F]{0,3}::[0-9a-fA-F:]*\b/[REDACTED_IPV6_ULA]/g' \
  -e 's/\bfe[89abAB][0-9a-fA-F]{0,2}(:[0-9a-fA-F]{0,4}){2,7}\b/[REDACTED_IPV6_LL]/g' \
  -e 's/\bfe[89abAB][0-9a-fA-F]{0,2}::[0-9a-fA-F:]*\b/[REDACTED_IPV6_LL]/g' \
  \
  `# 9. IPv4 Addresses: Generalized Redaction with Local Whitelisting` \
  `# Whitelist standard loopback, wildcard, netmasks, and default LAN (192.168.31.x / 192.168.32.x / 10.99.0.x)` \
  -e 's/\b127\.0\.0\.1\b/__PRESERVE_LOOPBACK__/g' \
  -e 's/\b0\.0\.0\.0\b/__PRESERVE_WILDCARD__/g' \
  -e 's/\b255\.255\.255\.[0-9]+\b/__PRESERVE_NETMASK__/g' \
  -e 's/\b192\.168\.31\./__PRESERVE_LAN_31__/g' \
  -e 's/\b192\.168\.32\./__PRESERVE_LAN_32__/g' \
  -e 's/\b10\.99\.0\./__PRESERVE_LAN_VPN__/g' \
  -e 's/\b192\.168\.100\.[0-9]+\b/[REDACTED_WAN_IP]/g' \
  `# Redact any other IPv4 address (Public IPs, WAN gateways, remote peers)` \
  -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/[REDACTED_PUBLIC_IP]/g' \
  `# Restore whitelisted local network tokens` \
  -e 's/__PRESERVE_LOOPBACK__/127.0.0.1/g' \
  -e 's/__PRESERVE_WILDCARD__/0.0.0.0/g' \
  -e 's/__PRESERVE_NETMASK__/255.255.255.0/g' \
  -e 's/__PRESERVE_LAN_31__/192.168.31./g' \
  -e 's/__PRESERVE_LAN_32__/192.168.32./g' \
  -e 's/__PRESERVE_LAN_VPN__/10.99.0./g'
