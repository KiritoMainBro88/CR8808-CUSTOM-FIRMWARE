//! Router System Telemetry & Resource Budget Parser
//!
//! Evaluates lightweight Rust telemetry for CR8818 256MB memory profile
//! and BoringTun process memory constraints (<15 MB VmRSS acceptance target).

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct MemoryTelemetry {
    pub mem_total_kb: u64,
    pub mem_free_kb: u64,
    pub mem_available_kb: u64,
    pub buffers_kb: u64,
    pub cached_kb: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MemoryHealthStatus {
    Optimal,
    WarningPressure,
    CriticalOomRisk,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ProcessMemory {
    pub pid: u32,
    pub vm_size_kb: u64,
    pub vm_rss_kb: u64,
    pub vm_peak_kb: u64,
}

impl MemoryTelemetry {
    pub fn parse_proc_meminfo(input: &str) -> Self {
        let mut telem = Self::default();
        for line in input.lines() {
            let mut parts = line.split_whitespace();
            let key = match parts.next() {
                Some(k) => k.trim_end_matches(':'),
                None => continue,
            };
            let val: u64 = match parts.next().and_then(|v| v.parse().ok()) {
                Some(v) => v,
                None => continue,
            };

            match key {
                "MemTotal" => telem.mem_total_kb = val,
                "MemFree" => telem.mem_free_kb = val,
                "MemAvailable" => telem.mem_available_kb = val,
                "Buffers" => telem.buffers_kb = val,
                "Cached" => telem.cached_kb = val,
                _ => {}
            }
        }
        telem
    }

    pub fn evaluate_health(&self) -> MemoryHealthStatus {
        // CR8818 256MB Profile: Linux MemTotal is ~182 MB (186,000 KB)
        // Warning threshold: MemAvailable < 25 MB (25,600 KB)
        // Critical threshold: MemAvailable < 10 MB (10,240 KB)
        if self.mem_available_kb < 10_240 {
            MemoryHealthStatus::CriticalOomRisk
        } else if self.mem_available_kb < 25_600 {
            MemoryHealthStatus::WarningPressure
        } else {
            MemoryHealthStatus::Optimal
        }
    }
}

impl ProcessMemory {
    pub fn parse_proc_status(pid: u32, input: &str) -> Self {
        let mut mem = Self {
            pid,
            ..Default::default()
        };
        for line in input.lines() {
            let mut parts = line.split_whitespace();
            let key = match parts.next() {
                Some(k) => k.trim_end_matches(':'),
                None => continue,
            };
            let val: u64 = match parts.next().and_then(|v| v.parse().ok()) {
                Some(v) => v,
                None => continue,
            };

            match key {
                "VmSize" => mem.vm_size_kb = val,
                "VmRSS" => mem.vm_rss_kb = val,
                "VmPeak" => mem.vm_peak_kb = val,
                _ => {}
            }
        }
        mem
    }

    /// Evaluates if BoringTun complies with the ACCEPTANCE_TARGET: VmRSS < 15 MB (15,360 KB)
    pub fn complies_with_boringtun_target(&self) -> bool {
        self.vm_rss_kb < 15_360
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_MEMINFO: &str = r#"
MemTotal:         186368 kB
MemFree:           45120 kB
MemAvailable:      52800 kB
Buffers:            4200 kB
Cached:            24300 kB
SwapTotal:             0 kB
SwapFree:              0 kB
"#;

    const SAMPLE_MEMINFO_PRESSURE: &str = r#"
MemTotal:         186368 kB
MemFree:            8192 kB
MemAvailable:      18432 kB
Buffers:            1024 kB
Cached:             9216 kB
"#;

    const SAMPLE_BORINGTUN_STATUS: &str = r#"
Name:   boringtun-cli
Umask:  0022
State:  S (sleeping)
Tgid:   1234
Pid:    1234
VmPeak:    18432 kB
VmSize:    16384 kB
VmHWM:      4096 kB
VmRSS:      3840 kB
VmData:     2048 kB
VmStk:       136 kB
VmExe:      1400 kB
"#;

    const SAMPLE_GO_STATUS: &str = r#"
Name:   wireguard-go
VmSize:   534528 kB
VmRSS:     18432 kB
"#;

    #[test]
    fn test_parse_meminfo_optimal() {
        let telem = MemoryTelemetry::parse_proc_meminfo(SAMPLE_MEMINFO);
        assert_eq!(telem.mem_total_kb, 186368);
        assert_eq!(telem.mem_free_kb, 45120);
        assert_eq!(telem.mem_available_kb, 52800);
        assert_eq!(telem.evaluate_health(), MemoryHealthStatus::Optimal);
    }

    #[test]
    fn test_parse_meminfo_pressure() {
        let telem = MemoryTelemetry::parse_proc_meminfo(SAMPLE_MEMINFO_PRESSURE);
        assert_eq!(telem.mem_available_kb, 18432);
        assert_eq!(telem.evaluate_health(), MemoryHealthStatus::WarningPressure);
    }

    #[test]
    fn test_boringtun_acceptance_compliance() {
        let proc_mem = ProcessMemory::parse_proc_status(1234, SAMPLE_BORINGTUN_STATUS);
        assert_eq!(proc_mem.vm_rss_kb, 3840);
        assert_eq!(proc_mem.vm_size_kb, 16384);
        assert!(proc_mem.complies_with_boringtun_target());
    }

    #[test]
    fn test_wireguard_go_exceeds_budget() {
        let proc_mem = ProcessMemory::parse_proc_status(5678, SAMPLE_GO_STATUS);
        assert_eq!(proc_mem.vm_rss_kb, 18432); // 18 MB exceeds 15 MB budget
        assert_eq!(proc_mem.vm_size_kb, 534528); // 522 MB VmSize virtual memory arena
        assert!(!proc_mem.complies_with_boringtun_target());
    }
}
