#!/bin/sh
# scripts/sanitize_telemetry.sh
# Multi-Layer Stream Sanitizer for Router Telemetry & Audit Logs
# Scrubbing: MACs, BSSIDs, SSIDs, Wi-Fi Keys, Serials, WireGuard Keys,
# Generalized Public/WAN IPv4, IPv6 (GUA 2000::/3, ULA fc00::/7, Link-Local fe80::/10),
# Compressed/Expanded IPv6, CIDR prefixes, Zone IDs, and Hexadecimal addresses in /proc/net/tcp(6).
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
  `# 6a. Hexadecimal IPv6 Addresses in /proc/net/if_inet6 (32 hex chars followed by ifindex, prefix, scope, flags, dev)` \
  -e 's/\b00000000000000000000000000000001([ \t]+[0-9a-fA-F]{2}[ \t]+[0-9a-fA-F]{2}[ \t]+[0-9a-fA-F]{2}[ \t]+[0-9a-fA-F]{2}[ \t]+[^ \t\r\n]+)/__PRESERVE_HEX_IFINET6_LOOPBACK__\1/g' \
  -e 's/\b[0-9A-Fa-f]{32}([ \t]+[0-9a-fA-F]{2}[ \t]+[0-9a-fA-F]{2}[ \t]+[0-9a-fA-F]{2}[ \t]+[0-9a-fA-F]{2}[ \t]+[^ \t\r\n]+)/[REDACTED_HEX_IF_INET6]\1/g' \
  -e 's/__PRESERVE_HEX_IFINET6_LOOPBACK__/00000000000000000000000000000001/g' \
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
  `# 8. IPv6 Mapped & Embedded IPv4 (::ffff:x.x.x.x, ::ffff:hhhh:hhhh, and 2001:db8::x.x.x.x)` \
  -e 's/(::ffff(:0{1,4})?:(([0-9]{1,3}\.){3}[0-9]{1,3}|[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}))(\/[0-9]{1,3})?(%[a-zA-Z0-9_-]+)?/[REDACTED_IPV6_MAPPED]/g' \
  -e 's/\b([0-9a-fA-F]{1,4}:)+(:[0-9a-fA-F]{1,4})*::?([0-9a-fA-F]{1,4}:)*([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,3})?(%[a-zA-Z0-9_-]+)?/[REDACTED_IPV6_EMBEDDED]/g' \
  \
  `# 9. IPv6 Multicast (ff00::/8)` \
  -e 's/\b(ff[0-9a-fA-F]{2}(:[0-9a-fA-F]{1,4}|:)+[0-9a-fA-F]{0,4})(\/[0-9]{1,3})?(%[a-zA-Z0-9_-]+)?/[REDACTED_IPV6_MC]/g' \
  \
  `# 10. IPv6 Addresses: GUA (2000::/3: 2xxx and 3xxx), ULA (fc00::/7), Link-Local (fe80::/10)` \
  -e 's/\b([23][0-9a-fA-F]{1,3})(:[0-9a-fA-F]{1,4}|:)+[0-9a-fA-F]{0,4}(\/[0-9]{1,3})?(%[a-zA-Z0-9_-]+)?/[REDACTED_IPV6_GUA]/g' \
  -e 's/\b(f[cdCD][0-9a-fA-F]{0,2})(:[0-9a-fA-F]{1,4}|:)+[0-9a-fA-F]{0,4}(\/[0-9]{1,3})?(%[a-zA-Z0-9_-]+)?/[REDACTED_IPV6_ULA]/g' \
  -e 's/\b(fe[89abAB][0-9a-fA-F]{0,1})(:[0-9a-fA-F]{1,4}|:)+[0-9a-fA-F]{0,4}(\/[0-9]{1,3})?(%[a-zA-Z0-9_-]+)?/[REDACTED_IPV6_LL]/g' \
  \
  `# 9. Netmask Preservation (Accurate group capture: preserve exact original value 255.255.255.X)` \
  -e 's/\b(255\.255\.255\.[0-9]+)\b/__NETMASK_\1__/g' \
  \
  `# 10. IPv4 Local Whitelist (Preserve loopback, wildcard, and default router subnets)` \
  -e 's/\b127\.0\.0\.1\b/__PRESERVE_LOOPBACK__/g' \
  -e 's/\b0\.0\.0\.0\b/__PRESERVE_WILDCARD__/g' \
  -e 's/\b192\.168\.31\./__PRESERVE_LAN_31__/g' \
  -e 's/\b192\.168\.32\./__PRESERVE_LAN_32__/g' \
  -e 's/\b10\.99\.0\./__PRESERVE_LAN_VPN__/g' \
  \
  `# 11. WAN Subnet Specific Redaction (e.g. 192.168.100.x)` \
  -e 's/\b192\.168\.100\.[0-9]+(\/[0-9]{1,2})?\b/[REDACTED_WAN_IP]/g' \
  \
  `# 12. Generalized Public IPv4 Redaction (Any other external/public IPv4 address with optional CIDR)` \
  -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,2})?\b/[REDACTED_PUBLIC_IP]/g' \
  \
  `# 13. Restore Whitelisted Tokens and Exact Original Netmasks` \
  -e 's/__NETMASK_(255\.255\.255\.[0-9]+)__/\1/g' \
  -e 's/__PRESERVE_LOOPBACK__/127.0.0.1/g' \
  -e 's/__PRESERVE_WILDCARD__/0.0.0.0/g' \
  -e 's/__PRESERVE_LAN_31__/192.168.31./g' \
  -e 's/__PRESERVE_LAN_32__/192.168.32./g' \
  -e 's/__PRESERVE_LAN_VPN__/10.99.0./g'
