#!/bin/sh
# Copyright (C) 2026 CR8808-CUSTOM-FIRMWARE Project
# Custom netifd protocol handler for userspace BoringTun WireGuard

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

proto_wireguard_boringtun_init_config() {
	proto_config_add_string "private_key"
	proto_config_add_int "listen_port"
	proto_config_add_array "addresses"
	proto_config_add_int "mtu"
	proto_config_add_int "threads"
	proto_config_add_string "log_level"
	no_device=1
	available=1
}

wireguard_boringtun_add_peer() {
	local peer_config="$1"
	local tmp_conf="$2"
	local config="$3"

	local public_key preshared_key endpoint_host endpoint_port persistent_keepalive route_allowed_ips
	config_get public_key "$peer_config" public_key
	config_get preshared_key "$peer_config" preshared_key
	config_get endpoint_host "$peer_config" endpoint_host
	config_get endpoint_port "$peer_config" endpoint_port
	config_get persistent_keepalive "$peer_config" persistent_keepalive
	config_get_bool route_allowed_ips "$peer_config" route_allowed_ips 1

	[ -n "$public_key" ] || return 0

	echo "" >> "$tmp_conf"
	echo "[Peer]" >> "$tmp_conf"
	echo "PublicKey = $public_key" >> "$tmp_conf"
	[ -n "$preshared_key" ] && echo "PresharedKey = $preshared_key" >> "$tmp_conf"

	if [ -n "$endpoint_host" ]; then
		local ep_str="$endpoint_host"
		[ -n "$endpoint_port" ] && ep_str="${endpoint_host}:${endpoint_port}"
		echo "Endpoint = $ep_str" >> "$tmp_conf"
		proto_add_host_dependency "$config" "$endpoint_host"
	fi

	[ -n "$persistent_keepalive" ] && echo "PersistentKeepalive = $persistent_keepalive" >> "$tmp_conf"

	local allowed_ips
	config_get allowed_ips "$peer_config" allowed_ips
	for aip in $allowed_ips; do
		echo "AllowedIPs = $aip" >> "$tmp_conf"
		if [ "$route_allowed_ips" -eq 1 ]; then
			case "$aip" in
				*/*)
					;;
				*:*)
					aip="${aip}/128"
					;;
				*)
					aip="${aip}/32"
					;;
			esac
			case "$aip" in
				*:*)
					proto_add_ipv6_route "${aip%%/*}" "${aip##*/}"
					;;
				*)
					proto_add_ipv4_route "${aip%%/*}" "${aip##*/}"
					;;
			esac
		fi
	done
}

proto_wireguard_boringtun_setup() {
	local config="$1"
	local iface="$2"

	local private_key listen_port addresses mtu threads log_level
	json_get_vars private_key listen_port addresses mtu threads log_level

	[ -n "$threads" ] || threads=2
	[ -n "$log_level" ] || log_level="error"

	# 1. Ensure /dev/net/tun exists and socket directory is prepared
	[ -c /dev/net/tun ] || modprobe tun 2>/dev/null || true
	mkdir -p /var/run/wireguard
	chmod 0700 /var/run/wireguard

	# 2. Start BoringTun userspace daemon if not running
	if [ ! -S "/var/run/wireguard/${iface}.sock" ]; then
		/usr/bin/boringtun \
			--threads "$threads" \
			--verbosity "$log_level" \
			--disable-drop-privileges \
			"$iface"

		local count=0
		while [ ! -S "/var/run/wireguard/${iface}.sock" ] && [ "$count" -lt 10 ]; do
			sleep 0.5
			count=$((count + 1))
		done
	fi

	if [ ! -S "/var/run/wireguard/${iface}.sock" ]; then
		proto_notify_error "$config" "BORINGTUN_START_FAILED"
		proto_block_restart "$config"
		return 1
	fi

	# 3. Configure MTU
	[ -n "$mtu" ] && ip link set dev "$iface" mtu "$mtu"

	# 4. Generate secure WireGuard configuration file with restricted umask
	local tmp_conf="/tmp/wg_${iface}.conf"
	local old_umask
	old_umask=$(umask)
	umask 077

	echo "[Interface]" > "$tmp_conf"
	echo "PrivateKey = $private_key" >> "$tmp_conf"
	[ -n "$listen_port" ] && echo "ListenPort = $listen_port" >> "$tmp_conf"

	# Parse and append peers from UCI network config
	config_load network
	config_foreach wireguard_boringtun_add_peer "wireguard_${config}" "$tmp_conf" "$config"
	config_foreach wireguard_boringtun_add_peer "wireguard_boringtun_${config}" "$tmp_conf" "$config"

	umask "$old_umask"

	# Apply cryptographic configuration via standard wg UAPI tool
	wg setconf "$iface" "$tmp_conf"
	rm -f "$tmp_conf"

	# 5. Bring up interface and bind IP addresses (IPv4 & IPv6)
	ip link set dev "$iface" up
	proto_init_update "$iface" 1

	for addr in $addresses; do
		case "$addr" in
			*/*)
				;;
			*:*)
				addr="${addr}/128"
				;;
			*)
				addr="${addr}/32"
				;;
		esac
		case "$addr" in
			*:*)
				proto_add_ipv6_address "${addr%%/*}" "${addr##*/}"
				;;
			*)
				proto_add_ipv4_address "${addr%%/*}" "${addr##*/}"
				;;
		esac
	done

	proto_send_update "$config"
}

proto_wireguard_boringtun_teardown() {
	local config="$1"
	local iface="$2"
	# Deleting tun device signals EOF to BoringTun worker threads, triggering clean exit
	ip link del dev "$iface" 2>/dev/null || true
	# Clean up socket and fallback process kill
	rm -f "/var/run/wireguard/${iface}.sock" 2>/dev/null || true
	pkill -f "boringtun.*${iface}" 2>/dev/null || true
	proto_init_update "$iface" 0
	proto_send_update "$config"
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol wireguard_boringtun
}
