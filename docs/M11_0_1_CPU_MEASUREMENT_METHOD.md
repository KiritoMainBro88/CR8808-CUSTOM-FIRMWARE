# MILESTONE M11.0.1: EMPIRICAL CPU DELTA MEASUREMENT & PACKET SCHEDULING SPECIFICATION

**Document ID:** `CR8808-M11.0.1-CPU-001`  
**Milestone:** `M11.0.1 – Security Incident Containment & Evidence Correction`  
**Target Subsystem:** Qualcomm IPQ5018 Dual-Core Cortex-A53 Linux Kernel Scheduler  
**Reporting Authority:** Gemini 3.8 Flash High – Lead Developer / Research Engineer  
**Receiving Authority:** ChatGPT – Chief Architect / Architecture Lead  
**Date:** November 11, 2026  
**Status:** Methodological Correction & Non-Intrusive Profiling Tool Specification  
**Mathematical Foundation:** Delta-Sampling Formulation across `/proc/stat`, `/proc/softirqs`, and `/proc/interrupts`

---

## 1. Executive Summary & Correction of Methodology

In Milestone M11, the report stated:
> *"CPU0 is saturated at 99.58% due to SoftIRQ processing while CPU1 sits idle."*

Under the Chief Architect's audit, **this conclusion is formally retracted as methodologically flawed**.

### The Core Error:
The `/proc/softirqs` counter (`NET_RX = 234,498,210` on CPU0 vs `974,907` on CPU1) is a **cumulative lifetime counter** that has been accumulating since the system booted (system uptime: 2 days, 5 hours, 45 minutes = 193,520 seconds).
- Calculating a simple ratio from cumulative counters ($234.5\text{M} / (234.5\text{M} + 0.97\text{M}) \approx 99.58\%$) proves that **historical interrupt delivery has been asymmetric**, but does **NOT** measure instantaneous CPU load or prove CPU saturation.
- Dividing 234.5M softirqs across 193,520 seconds yields an average of ~1,211 softirqs per second on CPU0. On a 1.0 GHz Cortex-A53 core, processing ~1,200 softirqs/s consumes only a fraction of one core's capacity under typical idle/medium conditions.

To evaluate CPU load and packet steering objectively, all future profiling must be conducted using **time-bounded delta sampling ($\Delta t$)** under defined baseline and load conditions.

---

## 2. Mathematical Delta-Sampling Formulation

To obtain authentic, instantaneous CPU utilization and interrupt rates, the system must take two snapshots separated by a precisely timed duration $\Delta t = t_2 - t_1$:

### 2.1 Per-Core CPU Utilization Formula (`/proc/stat`)
From `/proc/stat`, each CPU core line provides cumulative jiffies spent in different states:
$$\text{Line: } \text{cpu}N \quad u \quad n \quad s \quad i \quad w \quad x \quad y \quad z$$
where:
- $u$: user, $n$: nice, $s$: system, $i$: idle, $w$: iowait, $x$: irq, $y$: softirq, $z$: steal.

For each core ($N \in \{0, 1\}$) over interval $\Delta t$:
$$\Delta \text{Total}_N = \Delta u_N + \Delta n_N + \Delta s_N + \Delta i_N + \Delta w_N + \Delta x_N + \Delta y_N + \Delta z_N$$
$$\Delta \text{Active}_N = \Delta \text{Total}_N - \Delta i_N - \Delta w_N$$

$$\text{Instantaneous CPU}_N \text{ Utilization (\%)} = \left( \frac{\Delta \text{Active}_N}{\Delta \text{Total}_N} \right) \times 100\%$$
$$\text{Instantaneous CPU}_N \text{ SoftIRQ Share (\%)} = \left( \frac{\Delta y_N}{\Delta \text{Total}_N} \right) \times 100\%$$

### 2.2 Per-Core SoftIRQ Rate Formula (`/proc/softirqs`)
$$\text{Rate}(\text{NET\_RX}_N) = \frac{\text{NET\_RX}_N(t_2) - \text{NET\_RX}_N(t_1)}{\Delta t} \quad [\text{events/sec}]$$

$$\text{Active SoftIRQ Imbalance Ratio} = \frac{\Delta \text{NET\_RX}_0}{\Delta \text{NET\_RX}_0 + \Delta \text{NET\_RX}_1} \times 100\%$$

---

## 3. Dedicated Read-Only Delta Profiling Tool

Below is the standalone POSIX shell script designed to collect authentic delta metrics without installing third-party tools or modifying system state:

```sh
#!/bin/sh
# scripts/measure_cpu_deltas.sh
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
```

---

## 4. Empirical Evaluation Protocol for RPS (Receive Packet Steering)

RPS must be evaluated strictly as a **test hypothesis**, recognizing that steering packets across CPU cores involves trade-offs:

### 4.1 Potential Benefits:
- Distributes software packet processing (TCP checksums, conntrack hashing, WireGuard ChaCha20-Poly1305 decryption) to CPU1.
- Prevents CPU0 from hitting 100% utilization during heavy non-NSS traffic.

### 4.2 Potential Drawbacks & Hazards:
- **Inter-Processor Interrupts (IPIs):** RPS triggers cross-core IPIs to wake up CPU1, adding latency.
- **L1 Cache Thrashing:** Moving packet descriptor processing between cores invalidates L1 instruction and data caches.
- **Packet Reordering:** If flow hashing does not maintain per-flow affinity, multi-core scheduling can cause out-of-order packet delivery, triggering TCP retransmissions and throttling throughput.

### 4.3 Phased Testing Matrix (To be executed in M11.1 upon authorization):
```
+----------------------------------------------------------------------------------------------------+
|                                      RPS EXPERIMENTAL TEST MATRIX                                  |
+--------+------------------+---------------------+-------------------+------------------------------+
| Step   | State            | Test Workload       | Sampling Metric   | Success Criterion            |
+--------+------------------+---------------------+-------------------+------------------------------+
| Step 1 | Baseline (RPS=0) | Idle (30s sample)   | CPU Utilization % | Establish quiescent state.   |
+--------+------------------+---------------------+-------------------+------------------------------+
| Step 2 | Baseline (RPS=0) | VPN iperf3 (30s)    | Throughput, Ping  | Measure baseline VPN load,   |
|        |                  |                     | Jitter, CPU0/1 %  | max throughput & CPU0 load.  |
+--------+------------------+---------------------+-------------------+------------------------------+
| Step 3 | Trial (RPS=2 on  | VPN iperf3 (30s)    | Throughput, Ping  | PASS IF: Throughput $\ge$    |
|        | wg0 only)        |                     | Jitter, CPU0/1 %  | baseline AND Jitter $\le$ base|
|        |                  |                     |                   | AND CPU0 load drops $\ge$ 20%|
+--------+------------------+---------------------+-------------------+------------------------------+
| Step 4 | Verification     | Return to RPS=0     | Immediate verify  | Confirm instant rollback.    |
+--------+------------------+---------------------+-------------------+------------------------------+
```

No RPS configuration will be committed or made persistent without passing Step 3's empirical criteria.
