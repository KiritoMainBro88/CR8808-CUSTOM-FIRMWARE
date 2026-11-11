import os
import sys

base_dir = "/root/work/boringtun-boringtun-cli-0.7.1"

# 1. timers.rs
timers_path = os.path.join(base_dir, "boringtun/src/noise/timers.rs")
with open(timers_path, "r", encoding="utf-8") as f:
    c = f.read()
if "pub fn set_persistent_keepalive" not in c:
    c = c.replace(
        "    pub fn persistent_keepalive(&self) -> Option<u16> {",
        "    pub fn set_persistent_keepalive(&mut self, keepalive: Option<u16>) {\n        self.timers.persistent_keepalive = usize::from(keepalive.unwrap_or(0));\n    }\n\n    pub fn persistent_keepalive(&self) -> Option<u16> {"
    )
    with open(timers_path, "w", encoding="utf-8") as f:
        f.write(c)
    print("timers.rs patched")

# 2. noise/mod.rs
noise_path = os.path.join(base_dir, "boringtun/src/noise/mod.rs")
with open(noise_path, "r", encoding="utf-8") as f:
    c = f.read()
if "pub fn set_persistent_keepalive" not in c:
    c = c.replace(
        "    pub fn set_static_private(",
        "    pub fn set_persistent_keepalive(&mut self, keepalive: Option<u16>) {\n        self.timers.set_persistent_keepalive(keepalive);\n    }\n\n    pub fn set_static_private("
    )
    with open(noise_path, "w", encoding="utf-8") as f:
        f.write(c)
    print("noise/mod.rs patched")

# 3. peer.rs
peer_path = os.path.join(base_dir, "boringtun/src/device/peer.rs")
with open(peer_path, "r", encoding="utf-8") as f:
    c = f.read()
if "pub fn set_persistent_keepalive" not in c:
    c = c.replace(
        "    pub fn persistent_keepalive(&self) -> Option<u16> {",
        "    pub fn set_persistent_keepalive(&mut self, keepalive: Option<u16>) {\n        self.tunnel.set_persistent_keepalive(keepalive);\n    }\n\n    pub fn clear_allowed_ips(&mut self) {\n        self.allowed_ips.clear();\n    }\n\n    pub fn add_allowed_ip(&mut self, ip: AllowedIP) {\n        self.allowed_ips.insert(ip.addr, ip.cidr as _, ());\n    }\n\n    pub fn persistent_keepalive(&self) -> Option<u16> {"
    )
    with open(peer_path, "w", encoding="utf-8") as f:
        f.write(c)
    print("peer.rs patched")

# 4. device/mod.rs
mod_path = os.path.join(base_dir, "boringtun/src/device/mod.rs")
with open(mod_path, "r", encoding="utf-8") as f:
    c = f.read()

old_fn = """    #[allow(clippy::too_many_arguments)]
    fn update_peer(
        &mut self,
        pub_key: x25519::PublicKey,
        remove: bool,
        _replace_ips: bool,
        endpoint: Option<SocketAddr>,
        allowed_ips: &[AllowedIP],
        keepalive: Option<u16>,
        preshared_key: Option<[u8; 32]>,
    ) {
        if remove {
            // Completely remove a peer
            return self.remove_peer(&pub_key);
        }

        // Update an existing peer
        if self.peers.get(&pub_key).is_some() {
            // We already have a peer, we need to merge the existing config into the newly created one
            panic!("Modifying existing peers is not yet supported. Remove and add again instead.");
        }

        let next_index = self.next_index();
        let device_key_pair = self
            .key_pair
            .as_ref()
            .expect("Private key must be set first");

        let tunn = Tunn::new(
            device_key_pair.0.clone(),
            pub_key,
            preshared_key,
            keepalive,
            next_index,
            None,
        );

        let peer = Peer::new(tunn, next_index, endpoint, allowed_ips, preshared_key);

        let peer = Arc::new(Mutex::new(peer));
        self.peers.insert(pub_key, Arc::clone(&peer));
        self.peers_by_idx.insert(next_index, Arc::clone(&peer));

        for AllowedIP { addr, cidr } in allowed_ips {
            self.peers_by_ip
                .insert(*addr, *cidr as _, Arc::clone(&peer));
        }

        tracing::info!("Peer added");
    }"""

new_fn = """    #[allow(clippy::too_many_arguments)]
    fn update_peer(
        &mut self,
        pub_key: x25519::PublicKey,
        remove: bool,
        replace_ips: bool,
        endpoint: Option<SocketAddr>,
        allowed_ips: &[AllowedIP],
        keepalive: Option<u16>,
        preshared_key: Option<[u8; 32]>,
    ) -> i32 {
        if remove {
            self.remove_peer(&pub_key);
            return 0;
        }

        if let Some(existing_peer) = self.peers.get(&pub_key) {
            let p = existing_peer.lock();

            // Preshared key cannot be mutated mid-session in WireGuard without a new handshake
            if let Some(new_psk) = preshared_key {
                if p.preshared_key() != Some(&new_psk) {
                    tracing::warn!("In-place mutation of preshared_key is not supported; remove and re-add peer instead");
                    return libc::EOPNOTSUPP;
                }
            }

            // In-place update of endpoint (preserving session keys and handshake)
            if let Some(ep) = endpoint {
                p.set_endpoint(ep);
            }

            // In-place update of persistent keepalive
            if keepalive.is_some() {
                drop(p);
                let mut p_mut = existing_peer.lock();
                p_mut.set_persistent_keepalive(keepalive);
            } else {
                drop(p);
            }

            // In-place update of AllowedIPs (preserving session keys and handshake)
            if replace_ips {
                self.peers_by_ip
                    .remove(&|peer_arc: &Arc<Mutex<Peer>>| Arc::ptr_eq(existing_peer, peer_arc));
                let mut p = existing_peer.lock();
                p.clear_allowed_ips();
                for ip in allowed_ips {
                    p.add_allowed_ip(*ip);
                    self.peers_by_ip
                        .insert(ip.addr, ip.cidr as _, Arc::clone(existing_peer));
                }
            } else if !allowed_ips.is_empty() {
                let mut p = existing_peer.lock();
                for ip in allowed_ips {
                    if !p.is_allowed_ip(ip.addr) {
                        p.add_allowed_ip(*ip);
                        self.peers_by_ip
                            .insert(ip.addr, ip.cidr as _, Arc::clone(existing_peer));
                    }
                }
            }

            tracing::info!("Existing peer updated in-place without resetting session keys");
            return 0;
        }

        let next_index = self.next_index();
        let device_key_pair = match self.key_pair.as_ref() {
            Some(kp) => kp,
            None => {
                tracing::error!("Attempt to add peer to uninitialized device");
                return libc::EINVAL;
            }
        };

        let tunn = Tunn::new(
            device_key_pair.0.clone(),
            pub_key,
            preshared_key,
            keepalive,
            next_index,
            None,
        );

        let peer = Peer::new(tunn, next_index, endpoint, allowed_ips, preshared_key);

        let peer = Arc::new(Mutex::new(peer));
        self.peers.insert(pub_key, Arc::clone(&peer));
        self.peers_by_idx.insert(next_index, Arc::clone(&peer));

        for AllowedIP { addr, cidr } in allowed_ips {
            self.peers_by_ip
                .insert(*addr, *cidr as _, Arc::clone(&peer));
        }

        tracing::info!("Peer added");
        0
    }"""

if old_fn in c:
    c = c.replace(old_fn, new_fn)
    with open(mod_path, "w", encoding="utf-8") as f:
        f.write(c)
    print("device/mod.rs patched")
else:
    print("device/mod.rs old_fn not found")

# 5. api.rs
api_path = os.path.join(base_dir, "boringtun/src/device/api.rs")
with open(api_path, "r", encoding="utf-8") as f:
    c = f.read()

old_api_1 = """        if cmd.is_empty() {
            d.update_peer(
                public_key,
                remove,
                replace_ips,
                endpoint,
                allowed_ips.as_slice(),
                keepalive,
                preshared_key,
            );
            allowed_ips.clear(); //clear the vector content after update
            return 0; // Done
        }"""

new_api_1 = """        if cmd.is_empty() {
            let status = d.update_peer(
                public_key,
                remove,
                replace_ips,
                endpoint,
                allowed_ips.as_slice(),
                keepalive,
                preshared_key,
            );
            allowed_ips.clear(); //clear the vector content after update
            return status;
        }"""

old_api_2 = """                "public_key" => {
                    // Indicates a new peer section. Commit changes for current peer, and continue to next peer
                    d.update_peer(
                        public_key,
                        remove,
                        replace_ips,
                        endpoint,
                        allowed_ips.as_slice(),
                        keepalive,
                        preshared_key,
                    );
                    allowed_ips.clear(); //clear the vector content after update
                    match val.parse::<KeyBytes>() {
                        Ok(key_bytes) => public_key = key_bytes.0.into(),
                        Err(_) => return EINVAL,
                    }
                }"""

new_api_2 = """                "public_key" => {
                    let status = d.update_peer(
                        public_key,
                        remove,
                        replace_ips,
                        endpoint,
                        allowed_ips.as_slice(),
                        keepalive,
                        preshared_key,
                    );
                    allowed_ips.clear(); //clear the vector content after update
                    if status != 0 {
                        return status;
                    }
                    match val.parse::<KeyBytes>() {
                        Ok(key_bytes) => public_key = key_bytes.0.into(),
                        Err(_) => return EINVAL,
                    }
                }"""

if old_api_1 in c and old_api_2 in c:
    c = c.replace(old_api_1, new_api_1).replace(old_api_2, new_api_2)
    with open(api_path, "w", encoding="utf-8") as f:
        f.write(c)
    print("device/api.rs patched")
else:
    print("device/api.rs target not found")
