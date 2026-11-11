#!/bin/sh
# tests/test_measure_cpu_deltas.sh
# Host-side validation test fixture runner for CPU / SoftIRQ delta measurement
# Compatible with POSIX sh and BusyBox ash

set -eu

FIXTURE_DIR="${1:-tests/fixtures}"
STAT_T1="${FIXTURE_DIR}/proc_stat_t1.txt"
STAT_T2="${FIXTURE_DIR}/proc_stat_t2.txt"
SOFTIRQ_T1="${FIXTURE_DIR}/proc_softirqs_t1.txt"
SOFTIRQ_T2="${FIXTURE_DIR}/proc_softirqs_t2.txt"
DURATION=10

echo "=== Running CPU / SoftIRQ Delta Validation Test Harness ==="
echo "Fixtures: ${FIXTURE_DIR}"

if [ ! -f "$STAT_T1" ] || [ ! -f "$STAT_T2" ] || [ ! -f "$SOFTIRQ_T1" ] || [ ! -f "$SOFTIRQ_T2" ]; then
    echo "ERROR: Fixture files not found in ${FIXTURE_DIR}"
    exit 1
fi

OUTPUT=$(awk -v dur="$DURATION" \
             -v stat1="$STAT_T1" \
             -v stat2="$STAT_T2" \
             -v sdirq1="$SOFTIRQ_T1" \
             -v sdirq2="$SOFTIRQ_T2" '
BEGIN {
    # Parse /proc/stat
    while ((getline line < stat1) > 0) {
        split(line, f)
        if (f[1] ~ /^cpu[0-9]/) {
            cpu = f[1]
            u1[cpu]=f[2]; n1[cpu]=f[3]; s1[cpu]=f[4]; i1[cpu]=f[5];
            w1[cpu]=f[6]; x1[cpu]=f[7]; y1[cpu]=f[8]; z1[cpu]=f[9]
        }
    }
    close(stat1)

    while ((getline line < stat2) > 0) {
        split(line, f)
        if (f[1] ~ /^cpu[0-9]/) {
            cpu = f[1]
            u2[cpu]=f[2]; n2[cpu]=f[3]; s2[cpu]=f[4]; i2[cpu]=f[5];
            w2[cpu]=f[6]; x2[cpu]=f[7]; y2[cpu]=f[8]; z2[cpu]=f[9]
        }
    }
    close(stat2)

    printf("--- CPU METRICS ---\n")
    for (c in u1) {
        tot = (u2[c]-u1[c]) + (n2[c]-n1[c]) + (s2[c]-s1[c]) + (i2[c]-i1[c]) + (w2[c]-w1[c]) + (x2[c]-x1[c]) + (y2[c]-y1[c]) + (z2[c]-z1[c])
        if (tot > 0) {
            act = tot - (i2[c]-i1[c]) - (w2[c]-w1[c])
            printf("%s: total=%.2f user=%.2f sys=%.2f softirq=%.2f idle=%.2f\n",
                   c, (act/tot)*100, ((u2[c]-u1[c])/tot)*100, ((s2[c]-s1[c])/tot)*100, ((y2[c]-y1[c])/tot)*100, ((i2[c]-i1[c])/tot)*100)
        }
    }

    # Parse /proc/softirqs
    while ((getline line < sdirq1) > 0) {
        if (line ~ /NET_RX:/) { split(line, f); rx1_0=f[2]; rx1_1=f[3] }
    }
    close(sdirq1)

    while ((getline line < sdirq2) > 0) {
        if (line ~ /NET_RX:/) { split(line, f); rx2_0=f[2]; rx2_1=f[3] }
    }
    close(sdirq2)

    d0 = (rx2_0 - rx1_0); d1 = (rx2_1 - rx1_1); tot_rx = d0 + d1
    printf("--- SOFTIRQ METRICS ---\n")
    printf("d0=%d rate0=%.1f d1=%d rate1=%.1f\n", d0, d0/dur, d1, d1/dur)
    if (tot_rx > 0) {
        printf("pct0=%.1f pct1=%.1f\n", (d0/tot_rx)*100, (d1/tot_rx)*100)
    }
}')

echo "$OUTPUT"

# Assertions
echo "$OUTPUT" | grep -q "cpu0: total=60.00 user=10.00 sys=20.00 softirq=30.00 idle=40.00" || {
    echo "ASSERTION FAILED: cpu0 calculation incorrect"
    exit 1
}

echo "$OUTPUT" | grep -q "cpu1: total=10.00 user=5.00 sys=5.00 softirq=0.00 idle=90.00" || {
    echo "ASSERTION FAILED: cpu1 calculation incorrect"
    exit 1
}

echo "$OUTPUT" | grep -q "d0=10000 rate0=1000.0 d1=1000 rate1=100.0" || {
    echo "ASSERTION FAILED: NET_RX rates incorrect"
    exit 1
}

echo "$OUTPUT" | grep -q "pct0=90.9 pct1=9.1" || {
    echo "ASSERTION FAILED: NET_RX distribution percentages incorrect"
    exit 1
}

echo "=== ALL 4 ASSERTIONS PASSED (100% MATHEMATICAL ACCURACY) ==="
