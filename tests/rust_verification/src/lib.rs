//! CR8818 Rust Userspace Strategy Verification Library
//!
//! Provides comprehensive testing and validation of:
//! 1. Motorcomm YT9215SC DSA Tagging with independent C oracle parity
//! 2. WireGuard Protocol datagram packet parsing & fuzzing
//! 3. WireGuard Cross-Platform Userspace UAPI protocol state machine
//! 4. Signal handling fallback simulation (signalfd vs self-pipe)
//! 5. System telemetry & memory budget compliance for CR8818 256MB profile

pub mod yt921x_tag;
pub mod wireguard_packet;
pub mod wireguard_uapi;
pub mod signalfd_fallback;
pub mod telemetry;
