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
	proto_config_add_string "addresses"
	proto_config_add_int "mtu"
	no_device=1
	available=1
}

proto_wireguard_boringtun_setup() {
	local config="$1"
	local iface="$2"

	local private_key listen_port addresses mtu
	json_get_vars private_key listen_port addresses mtu

	# 1. Start BoringTun userspace daemon if not running
	if [ ! -S "/var/run/wireguard/${iface}.sock" ]; then
		/usr/bin/boringtun --threads 2 --verbosity error "$iface"
		sleep 1
	fi

	# 2. Configure MTU
	[ -n "$mtu" ] && ip link set dev "$iface" mtu "$mtu"

	# 3. Apply WireGuard cryptographic configuration via UAPI
	local tmp_conf="/tmp/wg_${iface}.conf"
	echo "[Interface]" > "$tmp_conf"
	echo "PrivateKey = $private_key" >> "$tmp_conf"
	[ -n "$listen_port" ] && echo "ListenPort = $listen_port" >> "$tmp_conf"

	wg setconf "$iface" "$tmp_conf"
	rm -f "$tmp_conf"

	# 4. Bring up interface and bind IP address
	ip link set dev "$iface" up
	proto_init_update "$iface" 1
	for addr in $addresses; do
		proto_add_ipv4_address "${addr%%/*}" "${addr##*/}"
	done
	proto_send_update "$config"
}

proto_wireguard_boringtun_teardown() {
	local config="$1"
	local iface="$2"
	ip link del dev "$iface" 2>/dev/null || true
	proto_init_update "$iface" 0
	proto_send_update "$config"
}

[ -n "$INCLUDE_ONLY" ] || {
	add_protocol wireguard_boringtun
}
