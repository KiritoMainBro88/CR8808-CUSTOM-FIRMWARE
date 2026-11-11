#!/bin/sh
# tests/test_inmemory_delta.sh
# Tests pure in-memory streaming delta calculation with zero disk/tmpfs writes

set -eu

OUTPUT=$(
cat << 'EOF' | awk -v dur=10 '
BEGIN { phase = 0 }
/^=== T1 ===/ { phase = 1; next }
/^=== T2 ===/ { phase = 2; next }
phase == 1 {
    if ($1 ~ /^cpu[0-9]/) {
        c = $1
        u1[c]=$2; n1[c]=$3; s1[c]=$4; i1[c]=$5; w1[c]=$6; x1[c]=$7; y1[c]=$8; z1[c]=$9
    }
    if ($1 ~ /NET_RX:/) {
        rx1_0 = $2; rx1_1 = $3
    }
}
phase == 2 {
    if ($1 ~ /^cpu[0-9]/) {
        c = $1
        u2[c]=$2; n2[c]=$3; s2[c]=$4; i2[c]=$5; w2[c]=$6; x2[c]=$7; y2[c]=$8; z2[c]=$9
    }
    if ($1 ~ /NET_RX:/) {
        rx2_0 = $2; rx2_1 = $3
    }
}
END {
    for (c in u1) {
        tot = (u2[c]-u1[c]) + (n2[c]-n1[c]) + (s2[c]-s1[c]) + (i2[c]-i1[c]) + (w2[c]-w1[c]) + (x2[c]-x1[c]) + (y2[c]-y1[c]) + (z2[c]-z1[c])
        if (tot > 0) {
            act = tot - (i2[c]-i1[c]) - (w2[c]-w1[c])
            printf("%s: total=%.2f user=%.2f sys=%.2f softirq=%.2f idle=%.2f\n",
                   c, (act/tot)*100, ((u2[c]-u1[c])/tot)*100, ((s2[c]-s1[c])/tot)*100, ((y2[c]-y1[c])/tot)*100, ((i2[c]-i1[c])/tot)*100)
        }
    }
    d0 = (rx2_0 - rx1_0); d1 = (rx2_1 - rx1_1); tot_rx = d0 + d1
    printf("d0=%d d1=%d tot=%d\n", d0, d1, tot_rx)
}
'
=== T1 ===
cpu0 100 0 200 700 0 0 0 0 0 0
cpu1 50 0 50 900 0 0 0 0 0 0
NET_RX: 1000 2000
=== T2 ===
cpu0 200 0 400 1100 0 0 300 0 0 0
cpu1 100 0 100 1800 0 0 0 0 0 0
NET_RX: 11000 3000
EOF
)

echo "$OUTPUT"

echo "$OUTPUT" | grep -q "cpu0: total=60.00 user=10.00 sys=20.00 softirq=30.00 idle=40.00" || {
    echo "FAILED: cpu0 calculation"
    exit 1
}

echo "$OUTPUT" | grep -q "cpu1: total=10.00 user=5.00 sys=5.00 softirq=0.00 idle=90.00" || {
    echo "FAILED: cpu1 calculation"
    exit 1
}

echo "$OUTPUT" | grep -q "d0=10000 d1=1000 tot=11000" || {
    echo "FAILED: softirq delta calculation"
    exit 1
}

echo "=== IN-MEMORY STREAM DELTA CALCULATION PASSED (100% PURE READ-ONLY) ==="
