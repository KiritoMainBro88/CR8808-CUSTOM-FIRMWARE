//! Standalone Rust Verification Test Runner for CR8818 Firmware

use rust_verification::yt921x_tag::*;
use rust_verification::wireguard_packet::*;
use rust_verification::wireguard_uapi::*;
use rust_verification::signalfd_fallback::*;
use rust_verification::telemetry::*;

fn main() {
    println!("====================================================================");
    println!("CR8818 Rust Userspace Strategy Verification Suite");
    println!("Architecture Directive: C + Rust Hybrid Strategy Validation");
    println!("====================================================================");

    let mut passed = 0;
    let mut total = 0;

    macro_rules! run_test {
        ($name:expr, $expr:expr) => {
            total += 1;
            print!("  [TEST {:02}] {} ... ", total, $name);
            if $expr {
                println!("\x1b[32mPASS\x1b[0m");
                passed += 1;
            } else {
                println!("\x1b[31mFAIL\x1b[0m");
            }
        };
    }

    println!("\n=== Group 1: Motorcomm YT9215SC DSA Tagging Parity ===");
    let frame0 = EtherFrame {
        dmac: [0x00, 0x11, 0x22, 0x33, 0x44, 0x55],
        smac: [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF],
        ethertype: 0x0800,
        payload: b"TEST".to_vec(),
    };
    let wire0 = yt921x_tag_xmit(&frame0, 0).expect("xmit 0 failed");
    run_test!("YT921x Port 0 wire bytes match C Oracle", wire0.len() == 26 && wire0[18..20] == [0x80, 0x01]);

    let wire3 = yt921x_tag_xmit(&frame0, 3).expect("xmit 3 failed");
    run_test!("YT921x Port 3 (WAN) Tx mask matches C Oracle (0x8008)", wire3[18..20] == [0x80, 0x08]);

    let wire8 = yt921x_tag_xmit(&frame0, 8).expect("xmit 8 failed");
    run_test!("YT921x Port 8 (CPU1) Tx mask matches C Oracle (0x8100)", wire8[18..20] == [0x81, 0x00]);

    run_test!("Out-of-range port 9 rejected", yt921x_tag_xmit(&frame0, 9) == Err(TagError::PortOutOfRange(9)));

    println!("\n=== Group 2: WireGuard Protocol Header Parsing & Validation ===");
    let mut wg_init = [0u8; WG_INITIATION_LEN];
    wg_init[0] = 1;
    wg_init[4..8].copy_from_slice(&0x55AA55AAu32.to_le_bytes());
    let parsed_init = parse_wireguard_packet(&wg_init);
    run_test!("Handshake Initiation (Type 1, 148B) parsed", matches!(parsed_init, Ok(WireGuardPacket::HandshakeInitiation { sender_index: 0x55AA55AA, .. })));

    let mut wg_data = vec![0u8; 64];
    wg_data[0] = 4;
    wg_data[4..8].copy_from_slice(&0x11223344u32.to_le_bytes());
    wg_data[8..16].copy_from_slice(&1000u64.to_le_bytes());
    let parsed_data = parse_wireguard_packet(&wg_data);
    run_test!("Transport Data (Type 4, >=32B) parsed with counter", matches!(parsed_data, Ok(WireGuardPacket::TransportData { receiver_index: 0x11223344, counter: 1000, .. })));

    let mut bad_reserved = wg_init;
    bad_reserved[2] = 0x01;
    run_test!("Reserved bytes violation rejected", matches!(parse_wireguard_packet(&bad_reserved), Err(PacketError::ReservedNonZero(_))));

    println!("\n=== Group 3: WireGuard Userspace UAPI Parser ===");
    run_test!("UAPI 'get=1' request parsed", parse_uapi_request("get=1\n\n") == Ok(UapiCommand::Get));

    let uapi_set_str = "set=1\nlisten_port=51820\nreplace_peers=true\n\n";
    let parsed_set = parse_uapi_request(uapi_set_str);
    run_test!("UAPI 'set=1' listen_port parsed", matches!(parsed_set, Ok(UapiCommand::Set(cfg)) if cfg.listen_port == Some(51820)));

    println!("\n=== Group 4: Signal Handling Fallback Simulation ===");
    let eng_native = SignalEngine::new_with_simulation(0).expect("native init");
    run_test!("Signalfd native mechanism selected on errno 0", eng_native.mechanism == SignalMechanism::Signalfd);

    let mut eng_fallback = SignalEngine::new_with_simulation(38).expect("fallback init");
    run_test!("Fallback pipe mechanism activated on ENOSYS (38)", eng_fallback.mechanism == SignalMechanism::FallbackPipe);

    eng_fallback.dispatch_signal(UnixSignal::SigTerm).unwrap();
    run_test!("Fallback engine handles SIGTERM cleanly", eng_fallback.termination_requested && !eng_fallback.is_active);

    println!("\n=== Group 5: CR8818 256MB System Telemetry & Process Budget ===");
    let meminfo = "MemTotal: 186368 kB\nMemFree: 45000 kB\nMemAvailable: 52000 kB\nBuffers: 4000 kB\nCached: 20000 kB\n";
    let telem = MemoryTelemetry::parse_proc_meminfo(meminfo);
    run_test!("CR8818 MemTotal correctly parsed (~182 MB)", telem.mem_total_kb == 186368);
    run_test!("CR8818 memory health status optimal", telem.evaluate_health() == MemoryHealthStatus::Optimal);

    let boringtun_status = "Name: boringtun-cli\nVmSize: 16384 kB\nVmRSS: 3840 kB\n";
    let proc_mem = ProcessMemory::parse_proc_status(100, boringtun_status);
    run_test!("BoringTun VmRSS 3.8 MB complies with <15 MB budget", proc_mem.complies_with_boringtun_target());

    println!("\n====================================================================");
    println!("Test Summary: {} Passed, {} Failed (Total: {})", passed, total - passed, total);
    println!("====================================================================");

    if passed != total {
        std::process::exit(1);
    }
}
