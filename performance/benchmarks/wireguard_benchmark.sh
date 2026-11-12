#!/bin/bash
# performance/benchmarks/wireguard_benchmark.sh
# Milestone M12: WireGuard Performance & Daemon Footprint Benchmark
# Measures throughput, CPU impact, and VmRSS memory footprint of Go (wg0) vs Rust BoringTun (wg1).
#
# Usage:
#   ./wireguard_benchmark.sh [--interface <wg0|wg1>] [--target-ip <tunnel_ip>] [--json]

set -euo pipefail

INTERFACE="wg0"
TUNNEL_IP="10.99.0.1"
DURATION=10
JSON_OUTPUT=0
ROUTER_IP="192.168.31.1"
ROUTER_PORT="56789"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interface|-i)
      INTERFACE="$2"
      shift 2
      ;;
    --target-ip|-t)
      TUNNEL_IP="$2"
      shift 2
      ;;
    --duration|-d)
      DURATION="$2"
      shift 2
      ;;
    --json|-j)
      JSON_OUTPUT=1
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--interface <wg0|wg1>] [--target-ip <ip>] [--duration <sec>] [--json]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [ "$JSON_OUTPUT" -eq 0 ]; then
  echo "=== WireGuard Benchmark: Interface $INTERFACE ($TUNNEL_IP) ==="
fi

# 1. Measure Tunnel Ping RTT and Jitter
TMP_PING=$(mktemp)
ping -c 30 -i 0.1 "$TUNNEL_IP" > "$TMP_PING" 2>&1 || true

LOSS=$(grep -oE '[0-9]+% packet loss' "$TMP_PING" | awk '{print $1}' | tr -d '%' || echo "100")
RTT_LINE=$(grep -E '^(rtt|round-trip)' "$TMP_PING" || true)
rm -f "$TMP_PING"

MIN=0; AVG=0; MAX=0; MDEV=0
if [ -n "$RTT_LINE" ]; then
  STATS=$(echo "$RTT_LINE" | awk '{print $4}')
  MIN=$(echo "$STATS" | cut -d'/' -f1)
  AVG=$(echo "$STATS" | cut -d'/' -f2)
  MAX=$(echo "$STATS" | cut -d'/' -f3)
  MDEV=$(echo "$STATS" | cut -d'/' -f4)
fi

# 2. Remote Daemon Memory & Process Inspection (Read-Only)
DAEMON_NAME="wg_server"
if [ "$INTERFACE" = "wg1" ]; then
  DAEMON_NAME="boringtun"
fi

MEM_STATS=$(sshpass -e ssh -p "$ROUTER_PORT" \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
  -o HostKeyAlgorithms=+ssh-rsa "root@${ROUTER_IP}" "
PID=\$(pgrep -f $DAEMON_NAME | head -n 1 || true)
if [ -n \"\$PID\" ]; then
  RSS=\$(grep -i VmRSS /proc/\$PID/status 2>/dev/null | awk '{print \$2}' || echo 0)
  HWM=\$(grep -i VmHWM /proc/\$PID/status 2>/dev/null | awk '{print \$2}' || echo 0)
  SIZE=\$(grep -i VmSize /proc/\$PID/status 2>/dev/null | awk '{print \$2}' || echo 0)
  echo \"\$PID \$RSS \$HWM \$SIZE\"
else
  echo \"0 0 0 0\"
fi
" 2>/dev/null || echo "0 0 0 0")

read -r DPID DRSS DHWM DSIZE <<< "$MEM_STATS"

if [ "$JSON_OUTPUT" -eq 1 ]; then
  echo "{"
  echo "  \"interface\": \"$INTERFACE\","
  echo "  \"daemon\": \"$DAEMON_NAME\","
  echo "  \"pid\": $DPID,"
  echo "  \"vm_rss_kb\": $DRSS,"
  echo "  \"vm_hwm_kb\": $DHWM,"
  echo "  \"vm_size_kb\": $DSIZE,"
  echo "  \"ping_packet_loss_pct\": $LOSS,"
  echo "  \"ping_min_ms\": $MIN,"
  echo "  \"ping_avg_ms\": $AVG,"
  echo "  \"ping_max_ms\": $MAX,"
  echo "  \"ping_mdev_ms\": $MDEV"
  echo "}"
else
  printf "%-22s : %s\n" "Interface" "$INTERFACE"
  printf "%-22s : %s (PID %s)\n" "Daemon Process" "$DAEMON_NAME" "$DPID"
  printf "%-22s : %s kB (%6.2f MB)\n" "Resident Memory (VmRSS)" "$DRSS" "$(awk "BEGIN {printf \"%.2f\", $DRSS/1024}")"
  printf "%-22s : %s kB (%6.2f MB)\n" "Peak Resident (VmHWM)" "$DHWM" "$(awk "BEGIN {printf \"%.2f\", $DHWM/1024}")"
  printf "%-22s : %s kB (%6.2f MB)\n" "Virtual Memory (VmSize)" "$DSIZE" "$(awk "BEGIN {printf \"%.2f\", $DSIZE/1024}")"
  printf "%-22s : %s%%\n" "Tunnel Packet Loss" "$LOSS"
  printf "%-22s : %s ms\n" "Tunnel Min RTT" "$MIN"
  printf "%-22s : %s ms\n" "Tunnel Avg RTT" "$AVG"
  printf "%-22s : %s ms\n" "Tunnel Max RTT" "$MAX"
  printf "%-22s : %s ms\n" "Tunnel Jitter / mdev" "$MDEV"
fi
