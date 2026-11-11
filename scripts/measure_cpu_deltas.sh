#!/bin/sh
# scripts/measure_cpu_deltas.sh
# Time-bounded Delta-Sampling Measurement for CPU, SoftIRQ, and Interrupts on OpenWrt / QSDK
# Usage: ./measure_cpu_deltas.sh [duration_seconds]

DURATION="${1:-10}"
echo "Collecting baseline snapshot t1 at $(date)..."

# Capture Snapshot 1
cat /proc/stat > /tmp/stat_t1
cat /proc/softirqs > /tmp/softirqs_t1
cat /proc/interrupts > /tmp/interrupts_t1

echo "Sampling over ${DURATION} seconds..."
sleep "$DURATION"

# Capture Snapshot 2
cat /proc/stat > /tmp/stat_t2
cat /proc/softirqs > /tmp/softirqs_t2
cat /proc/interrupts > /tmp/interrupts_t2

echo "Analyzing deltas over ${DURATION}s interval..."

# Parse /proc/stat deltas
awk -v dur="$DURATION" '
BEGIN {
    # Read t1
    while ((getline line < "/tmp/stat_t1") > 0) {
        split(line, f)
        if (f[1] ~ /^cpu[0-9]/) {
            cpu = f[1]
            u1[cpu]=f[2]; n1[cpu]=f[3]; s1[cpu]=f[4]; i1[cpu]=f[5];
            w1[cpu]=f[6]; x1[cpu]=f[7]; y1[cpu]=f[8]; z1[cpu]=f[9]
        }
    }
    close("/tmp/stat_t1")
    # Read t2
    while ((getline line < "/tmp/stat_t2") > 0) {
        split(line, f)
        if (f[1] ~ /^cpu[0-9]/) {
            cpu = f[1]
            u2[cpu]=f[2]; n2[cpu]=f[3]; s2[cpu]=f[4]; i2[cpu]=f[5];
            w2[cpu]=f[6]; x2[cpu]=f[7]; y2[cpu]=f[8]; z2[cpu]=f[9]
        }
    }
    close("/tmp/stat_t2")

    printf("\n==================== CPU UTILIZATION OVER %d SECONDS ====================\n", dur)
    printf("%-8s %-12s %-12s %-12s %-12s %-12s\n", "Core", "Total%", "User%", "System%", "SoftIRQ%", "Idle%")
    for (c in u1) {
        tot = (u2[c]-u1[c]) + (n2[c]-n1[c]) + (s2[c]-s1[c]) + (i2[c]-i1[c]) + (w2[c]-w1[c]) + (x2[c]-x1[c]) + (y2[c]-y1[c]) + (z2[c]-z1[c])
        if (tot > 0) {
            act = tot - (i2[c]-i1[c]) - (w2[c]-w1[c])
            printf("%-8s %-12.2f %-12.2f %-12.2f %-12.2f %-12.2f\n", 
                   c, (act/tot)*100, ((u2[c]-u1[c])/tot)*100, ((s2[c]-s1[c])/tot)*100, ((y2[c]-y1[c])/tot)*100, ((i2[c]-i1[c])/tot)*100)
        }
    }
}'

# Parse /proc/softirqs NET_RX delta
awk -v dur="$DURATION" '
BEGIN {
    while ((getline line < "/tmp/softirqs_t1") > 0) {
        if (line ~ /NET_RX:/) { split(line, f); rx1_0=f[2]; rx1_1=f[3] }
    }
    close("/tmp/softirqs_t1")
    while ((getline line < "/tmp/softirqs_t2") > 0) {
        if (line ~ /NET_RX:/) { split(line, f); rx2_0=f[2]; rx2_1=f[3] }
    }
    close("/tmp/softirqs_t2")

    d0 = (rx2_0 - rx1_0); d1 = (rx2_1 - rx1_1); tot = d0 + d1
    printf("\n==================== NET_RX SOFTIRQ DELTAS OVER %d SECONDS ====================\n", dur)
    printf("CPU0 NET_RX Delta: %d events (%.1f/sec)\n", d0, d0/dur)
    printf("CPU1 NET_RX Delta: %d events (%.1f/sec)\n", d1, d1/dur)
    if (tot > 0) {
        printf("Current Window Distribution: CPU0 = %.1f%%, CPU1 = %.1f%%\n", (d0/tot)*100, (d1/tot)*100)
    } else {
        printf("Current Window Distribution: 0 packets processed in software path.\n")
    }
}'

rm -f /tmp/stat_t1 /tmp/stat_t2 /tmp/softirqs_t1 /tmp/softirqs_t2 /tmp/interrupts_t1 /tmp/interrupts_t2
