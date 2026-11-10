//! WireGuard Datagram Packet Parsing and Header Validation in Rust
//!
//! Implements strict parsing and fuzzing against WireGuard Protocol Specification:
//! - Type 1: Handshake Initiation (148 bytes)
//! - Type 2: Handshake Response (92 bytes)
//! - Type 3: Cookie Reply (64 bytes)
//! - Type 4: Transport Data Packet (>= 32 bytes)

pub const WG_INITIATION_LEN: usize = 148;
pub const WG_RESPONSE_LEN: usize = 92;
pub const WG_COOKIE_REPLY_LEN: usize = 64;
pub const WG_DATA_MIN_LEN: usize = 32;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PacketError {
    Truncated { expected: usize, actual: usize },
    UnknownMessageType(u8),
    ReservedNonZero([u8; 3]),
    EmptyPayload,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WireGuardPacket<'a> {
    HandshakeInitiation {
        sender_index: u32,
        ephemeral: &'a [u8; 32],
        encrypted_static: &'a [u8; 48],
        encrypted_timestamp: &'a [u8; 28],
        mac1: &'a [u8; 16],
        mac2: &'a [u8; 16],
    },
    HandshakeResponse {
        sender_index: u32,
        receiver_index: u32,
        ephemeral: &'a [u8; 32],
        encrypted_empty: &'a [u8; 16],
        mac1: &'a [u8; 16],
        mac2: &'a [u8; 16],
    },
    CookieReply {
        receiver_index: u32,
        nonce: &'a [u8; 24],
        encrypted_cookie: &'a [u8; 32],
    },
    TransportData {
        receiver_index: u32,
        counter: u64,
        encrypted_payload: &'a [u8],
    },
}

pub fn parse_wireguard_packet(data: &[u8]) -> Result<WireGuardPacket<'_>, PacketError> {
    if data.len() < 4 {
        return Err(PacketError::Truncated {
            expected: 4,
            actual: data.len(),
        });
    }

    let msg_type = data[0];
    let reserved = [data[1], data[2], data[3]];
    if reserved != [0, 0, 0] {
        return Err(PacketError::ReservedNonZero(reserved));
    }

    match msg_type {
        1 => {
            if data.len() < WG_INITIATION_LEN {
                return Err(PacketError::Truncated {
                    expected: WG_INITIATION_LEN,
                    actual: data.len(),
                });
            }
            let sender_index = u32::from_le_bytes(data[4..8].try_into().unwrap());
            let ephemeral: &[u8; 32] = data[8..40].try_into().unwrap();
            let encrypted_static: &[u8; 48] = data[40..88].try_into().unwrap();
            let encrypted_timestamp: &[u8; 28] = data[88..116].try_into().unwrap();
            let mac1: &[u8; 16] = data[116..132].try_into().unwrap();
            let mac2: &[u8; 16] = data[132..148].try_into().unwrap();

            Ok(WireGuardPacket::HandshakeInitiation {
                sender_index,
                ephemeral,
                encrypted_static,
                encrypted_timestamp,
                mac1,
                mac2,
            })
        }
        2 => {
            if data.len() < WG_RESPONSE_LEN {
                return Err(PacketError::Truncated {
                    expected: WG_RESPONSE_LEN,
                    actual: data.len(),
                });
            }
            let sender_index = u32::from_le_bytes(data[4..8].try_into().unwrap());
            let receiver_index = u32::from_le_bytes(data[8..12].try_into().unwrap());
            let ephemeral: &[u8; 32] = data[12..44].try_into().unwrap();
            let encrypted_empty: &[u8; 16] = data[44..60].try_into().unwrap();
            let mac1: &[u8; 16] = data[60..76].try_into().unwrap();
            let mac2: &[u8; 16] = data[76..92].try_into().unwrap();

            Ok(WireGuardPacket::HandshakeResponse {
                sender_index,
                receiver_index,
                ephemeral,
                encrypted_empty,
                mac1,
                mac2,
            })
        }
        3 => {
            if data.len() < WG_COOKIE_REPLY_LEN {
                return Err(PacketError::Truncated {
                    expected: WG_COOKIE_REPLY_LEN,
                    actual: data.len(),
                });
            }
            let receiver_index = u32::from_le_bytes(data[4..8].try_into().unwrap());
            let nonce: &[u8; 24] = data[8..32].try_into().unwrap();
            let encrypted_cookie: &[u8; 32] = data[32..64].try_into().unwrap();

            Ok(WireGuardPacket::CookieReply {
                receiver_index,
                nonce,
                encrypted_cookie,
            })
        }
        4 => {
            if data.len() < WG_DATA_MIN_LEN {
                return Err(PacketError::Truncated {
                    expected: WG_DATA_MIN_LEN,
                    actual: data.len(),
                });
            }
            let receiver_index = u32::from_le_bytes(data[4..8].try_into().unwrap());
            let counter = u64::from_le_bytes(data[8..16].try_into().unwrap());
            let encrypted_payload = &data[16..];

            Ok(WireGuardPacket::TransportData {
                receiver_index,
                counter,
                encrypted_payload,
            })
        }
        other => Err(PacketError::UnknownMessageType(other)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_valid_handshake_initiation() {
        let mut pkt = [0u8; WG_INITIATION_LEN];
        pkt[0] = 1; // Handshake initiation
        pkt[4..8].copy_from_slice(&0x12345678u32.to_le_bytes()); // sender index

        let parsed = parse_wireguard_packet(&pkt).expect("parse initiation failed");
        match parsed {
            WireGuardPacket::HandshakeInitiation { sender_index, .. } => {
                assert_eq!(sender_index, 0x12345678);
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn test_parse_valid_handshake_response() {
        let mut pkt = [0u8; WG_RESPONSE_LEN];
        pkt[0] = 2; // Handshake response
        pkt[4..8].copy_from_slice(&100u32.to_le_bytes()); // sender index
        pkt[8..12].copy_from_slice(&200u32.to_le_bytes()); // receiver index

        let parsed = parse_wireguard_packet(&pkt).expect("parse response failed");
        match parsed {
            WireGuardPacket::HandshakeResponse {
                sender_index,
                receiver_index,
                ..
            } => {
                assert_eq!(sender_index, 100);
                assert_eq!(receiver_index, 200);
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn test_parse_valid_transport_data() {
        let mut pkt = vec![0u8; 64];
        pkt[0] = 4; // Data packet
        pkt[4..8].copy_from_slice(&0xABCDEF01u32.to_le_bytes()); // receiver index
        pkt[8..16].copy_from_slice(&42u64.to_le_bytes()); // counter
        pkt[16..].fill(0x55);

        let parsed = parse_wireguard_packet(&pkt).expect("parse data failed");
        match parsed {
            WireGuardPacket::TransportData {
                receiver_index,
                counter,
                encrypted_payload,
            } => {
                assert_eq!(receiver_index, 0xABCDEF01);
                assert_eq!(counter, 42);
                assert_eq!(encrypted_payload.len(), 48);
                assert_eq!(encrypted_payload[0], 0x55);
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn test_parse_valid_cookie_reply() {
        let mut pkt = [0u8; WG_COOKIE_REPLY_LEN];
        pkt[0] = 3; // Cookie reply
        pkt[4..8].copy_from_slice(&0x55AA55AAu32.to_le_bytes()); // receiver index
        pkt[8..32].fill(0x11); // nonce
        pkt[32..64].fill(0x22); // encrypted cookie

        let parsed = parse_wireguard_packet(&pkt).expect("parse cookie reply failed");
        match parsed {
            WireGuardPacket::CookieReply {
                receiver_index,
                nonce,
                encrypted_cookie,
            } => {
                assert_eq!(receiver_index, 0x55AA55AA);
                assert_eq!(nonce[0], 0x11);
                assert_eq!(encrypted_cookie[0], 0x22);
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn test_reject_reserved_nonzero() {
        let mut pkt = [0u8; WG_INITIATION_LEN];
        pkt[0] = 1;
        pkt[1] = 0xFF; // Reserved must be 0

        assert_eq!(
            parse_wireguard_packet(&pkt),
            Err(PacketError::ReservedNonZero([0xFF, 0, 0]))
        );
    }

    #[test]
    fn test_reject_truncated_packets() {
        let pkt = [1, 0, 0, 0, 1, 2, 3]; // 7 bytes, expected 148 for type 1
        assert_eq!(
            parse_wireguard_packet(&pkt),
            Err(PacketError::Truncated {
                expected: 148,
                actual: 7
            })
        );
    }

    #[test]
    fn test_fuzz_wireguard_parser_panic_freedom() {
        let mut seed: u64 = 0xDEADBEEFCAFEBABE;
        let mut rng = move || {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            (seed >> 32) as u32
        };

        for _ in 0..10_000 {
            let len = (rng() % 256) as usize;
            let mut buf = vec![0u8; len];
            for b in buf.iter_mut() {
                *b = (rng() & 0xFF) as u8;
            }

            // Guaranteed panic-free
            let _ = parse_wireguard_packet(&buf);
        }
    }
}
