//! WireGuard Cross-Platform Userspace UAPI Parser and Validator
//!
//! Implements Jason Donenfeld's WireGuard Userspace UAPI Specification:
//! Supports `get=1`, `set=1`, parsing keys, endpoints, allowed-ips, and errno responses.

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct UapiConfig {
    pub private_key: Option<String>,
    pub listen_port: Option<u16>,
    pub fwmark: Option<u32>,
    pub replace_peers: bool,
    pub peers: Vec<UapiPeer>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct UapiPeer {
    pub public_key: String,
    pub preshared_key: Option<String>,
    pub endpoint: Option<String>,
    pub persistent_keepalive: Option<u16>,
    pub replace_allowed_ips: bool,
    pub allowed_ips: Vec<String>,
    pub remove: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UapiCommand {
    Get,
    Set(UapiConfig),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UapiError {
    EmptyCommand,
    InvalidCommand(String),
    MalformedLine(String),
    InvalidKeyLength(usize),
    InvalidPort(String),
    InvalidFwmark(String),
    MissingPeerPublicKey,
}

pub fn parse_uapi_request(input: &str) -> Result<UapiCommand, UapiError> {
    let mut lines = input.lines();
    let first_line = lines.next().ok_or(UapiError::EmptyCommand)?;

    match first_line.trim() {
        "get=1" => Ok(UapiCommand::Get),
        "set=1" => {
            let mut config = UapiConfig::default();
            let mut current_peer: Option<UapiPeer> = None;

            for line in lines {
                let trimmed = line.trim();
                if trimmed.is_empty() {
                    continue;
                }
                let mut parts = trimmed.splitn(2, '=');
                let key = parts.next().unwrap();
                let val = parts.next().ok_or_else(|| UapiError::MalformedLine(trimmed.to_string()))?;

                match key {
                    "private_key" => {
                        validate_hex_key(val)?;
                        config.private_key = Some(val.to_string());
                    }
                    "listen_port" => {
                        let port: u16 = val.parse().map_err(|_| UapiError::InvalidPort(val.to_string()))?;
                        config.listen_port = Some(port);
                    }
                    "fwmark" => {
                        let mark: u32 = val.parse().map_err(|_| UapiError::InvalidFwmark(val.to_string()))?;
                        config.fwmark = Some(mark);
                    }
                    "replace_peers" => {
                        config.replace_peers = val == "true";
                    }
                    "public_key" => {
                        validate_hex_key(val)?;
                        if let Some(peer) = current_peer.take() {
                            config.peers.push(peer);
                        }
                        current_peer = Some(UapiPeer {
                            public_key: val.to_string(),
                            ..Default::default()
                        });
                    }
                    "preshared_key" => {
                        validate_hex_key(val)?;
                        if let Some(ref mut peer) = current_peer {
                            peer.preshared_key = Some(val.to_string());
                        } else {
                            return Err(UapiError::MissingPeerPublicKey);
                        }
                    }
                    "endpoint" => {
                        if let Some(ref mut peer) = current_peer {
                            peer.endpoint = Some(val.to_string());
                        } else {
                            return Err(UapiError::MissingPeerPublicKey);
                        }
                    }
                    "persistent_keepalive_interval" => {
                        let ka: u16 = val.parse().map_err(|_| UapiError::InvalidPort(val.to_string()))?;
                        if let Some(ref mut peer) = current_peer {
                            peer.persistent_keepalive = Some(ka);
                        } else {
                            return Err(UapiError::MissingPeerPublicKey);
                        }
                    }
                    "replace_allowed_ips" => {
                        if let Some(ref mut peer) = current_peer {
                            peer.replace_allowed_ips = val == "true";
                        } else {
                            return Err(UapiError::MissingPeerPublicKey);
                        }
                    }
                    "allowed_ip" => {
                        if let Some(ref mut peer) = current_peer {
                            peer.allowed_ips.push(val.to_string());
                        } else {
                            return Err(UapiError::MissingPeerPublicKey);
                        }
                    }
                    "remove" => {
                        if let Some(ref mut peer) = current_peer {
                            peer.remove = val == "true";
                        } else {
                            return Err(UapiError::MissingPeerPublicKey);
                        }
                    }
                    _ => {} // Ignore unrecognized extension keys
                }
            }

            if let Some(peer) = current_peer {
                config.peers.push(peer);
            }

            Ok(UapiCommand::Set(config))
        }
        other => Err(UapiError::InvalidCommand(other.to_string())),
    }
}

pub fn serialize_uapi_get_response(config: &UapiConfig, errno: i32) -> String {
    let mut out = String::new();
    if let Some(ref key) = config.private_key {
        out.push_str(&format!("private_key={}\n", key));
    }
    if let Some(port) = config.listen_port {
        out.push_str(&format!("listen_port={}\n", port));
    }
    if let Some(fwmark) = config.fwmark {
        out.push_str(&format!("fwmark={}\n", fwmark));
    }

    for peer in &config.peers {
        out.push_str(&format!("public_key={}\n", peer.public_key));
        if let Some(ref psk) = peer.preshared_key {
            out.push_str(&format!("preshared_key={}\n", psk));
        }
        if let Some(ref ep) = peer.endpoint {
            out.push_str(&format!("endpoint={}\n", ep));
        }
        if let Some(ka) = peer.persistent_keepalive {
            out.push_str(&format!("persistent_keepalive_interval={}\n", ka));
        }
        for ip in &peer.allowed_ips {
            out.push_str(&format!("allowed_ip={}\n", ip));
        }
    }

    out.push_str(&format!("errno={}\n\n", errno));
    out
}

fn validate_hex_key(key: &str) -> Result<(), UapiError> {
    if key.len() != 64 {
        return Err(UapiError::InvalidKeyLength(key.len()));
    }
    if !key.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(UapiError::MalformedLine(format!("non-hex key: {}", key)));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    const DUMMY_KEY_1: &str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const DUMMY_KEY_2: &str = "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210";

    #[test]
    fn test_parse_uapi_get() {
        let req = "get=1\n\n";
        assert_eq!(parse_uapi_request(req), Ok(UapiCommand::Get));
    }

    #[test]
    fn test_parse_uapi_set_full() {
        let req = format!(
            "set=1\nprivate_key={}\nlisten_port=51821\nreplace_peers=true\npublic_key={}\nendpoint=198.51.100.1:51820\nallowed_ip=0.0.0.0/0\npersistent_keepalive_interval=25\n\n",
            DUMMY_KEY_1, DUMMY_KEY_2
        );

        let parsed = parse_uapi_request(&req).expect("parse set failed");
        match parsed {
            UapiCommand::Set(cfg) => {
                assert_eq!(cfg.private_key.as_deref(), Some(DUMMY_KEY_1));
                assert_eq!(cfg.listen_port, Some(51821));
                assert!(cfg.replace_peers);
                assert_eq!(cfg.peers.len(), 1);
                assert_eq!(cfg.peers[0].public_key, DUMMY_KEY_2);
                assert_eq!(cfg.peers[0].endpoint.as_deref(), Some("198.51.100.1:51820"));
                assert_eq!(cfg.peers[0].allowed_ips, vec!["0.0.0.0/0"]);
                assert_eq!(cfg.peers[0].persistent_keepalive, Some(25));
            }
            _ => panic!("wrong command variant"),
        }
    }

    #[test]
    fn test_reject_invalid_key_length() {
        let req = "set=1\nprivate_key=deadbeef\n\n";
        assert_eq!(
            parse_uapi_request(req),
            Err(UapiError::InvalidKeyLength(8))
        );
    }

    #[test]
    fn test_serialize_roundtrip_response() {
        let config = UapiConfig {
            private_key: Some(DUMMY_KEY_1.to_string()),
            listen_port: Some(51820),
            fwmark: None,
            replace_peers: false,
            peers: vec![UapiPeer {
                public_key: DUMMY_KEY_2.to_string(),
                endpoint: Some("1.2.3.4:51820".to_string()),
                allowed_ips: vec!["10.0.0.2/32".to_string()],
                persistent_keepalive: Some(15),
                ..Default::default()
            }],
        };

        let resp = serialize_uapi_get_response(&config, 0);
        assert!(resp.contains(&format!("private_key={}", DUMMY_KEY_1)));
        assert!(resp.contains("listen_port=51820"));
        assert!(resp.contains(&format!("public_key={}", DUMMY_KEY_2)));
        assert!(resp.contains("endpoint=1.2.3.4:51820"));
        assert!(resp.contains("allowed_ip=10.0.0.2/32"));
        assert!(resp.contains("persistent_keepalive_interval=15"));
        assert!(resp.ends_with("errno=0\n\n"));
    }
}
