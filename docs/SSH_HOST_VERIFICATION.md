# SSH Host Key Pinning & Out-of-Band Authentication Specification

- **Document ID:** `docs/SSH_HOST_VERIFICATION.md`
- **Target Device:** Xiaomi CR8808 Ver.B (Internal Codename: `CR8818`, Profile: `ap-mp03.3`)
- **Authority:** Chief Architect Directive M11.1.0.2 / Lead Systems Engineer (Gemini)
- **Status:** **ACTIVE SPECIFICATION**

---

## 1. Problem Statement: Vulnerability of Trust-On-First-Use (TOFU)

In prior scripts, host authentication was performed via:
```sh
ssh-keyscan -p "$ROUTER_PORT" "$ROUTER_IP" 2>/dev/null > "$KNOWN_HOSTS_FILE"
ssh -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" ...
```
While this prevented SSH from prompting interactively, **it inherently implemented Trust-On-First-Use (TOFU)**:
1. If an active Man-in-the-Middle (MitM) adversary exists on the local LAN or upstream gateway at the moment `ssh-keyscan` is executed, the script blindly downloads and trusts the attacker's public key.
2. Enabling `StrictHostKeyChecking=yes` against a dynamically downloaded key offers zero protection against initial interception.
3. To achieve cryptographic assurance, the target router's host key must be **pinned out-of-band** and cryptographically validated before any connection is attempted.

---

## 2. Pinned Cryptographic Identity of CR8808 Ver.B (RA82)

The physical device's Dropbear SSH daemon identity has been recorded and pinned:

- **Key Algorithm:** RSA 2048-bit (`ssh-rsa`)
- **Public Key File:** [`config/cr8818_host_key.pub`](file:///D:/vibecode/CR8808-CUSTOM-FIRMWARE/config/cr8818_host_key.pub)
- **Cryptographic Fingerprints:**
  - **SHA-256 Fingerprint:** `SHA256:feZ+NfroyCIlYrC74Z1ZazUSby+WqxRxZM63Q6Q9HmM`
  - **MD5 Fingerprint:** `MD5:d9:83:8c:a3:23:fa:54:95:52:1e:bb:96:a9:85:cf:32`
- **Key Body:**
  ```text
  AAAAB3NzaC1yc2EAAAADAQABAAABAQDs/ojWVnbLTVelbMXmOgIwGUKUMpw8mXMhmycIo8vXBYdux9XNyEaW3L5MY4Pq8JwBScYw0j4DFx+atYtgF0TmRzEJfGm0NnbYz6qukpREKKAe0+IadbxTMekxRRS4/eMbG9QYwcPqrsUiHT7Qy/XTV/IiWslMargB2l8RsEjIlQYt6TlNVSEP0YzrbS+wStQ+BBCgc+N6FvsvYeWerJJKO2v4ICz9iBi1r/4OSlxJ+loHcrA5R7pHUjMx578RgJABoGhmZM+eKG8Rsxbz1GvEioSDxh/e/yYAuDm5zdNFHbX1YMrXrLg4gULugPpjRsRyxjLlMNPUYmtwQyw6i/Xn
  ```

### 2.1 Host Key Provenance & Trust Boundary Limitations

In strict adherence to Chief Architect Directive M11.1.0.3, the provenance of this pinned host key is formally disclosed:

1. **Origin of Key Baseline:** The host key and fingerprint were extracted from the operator workstation's historical SSH cache (`%USERPROFILE%\.ssh\known_hosts` entry bound to port `56789`), created during prior management sessions of this physical unit.
2. **What Key Pinning Guarantees:** 
   - Pinning eliminates dynamic Trust-On-First-Use (`ssh-keyscan`) vulnerability.
   - It strictly guarantees that no future SSH connection will proceed if the server presents any key other than this pinned RSA key. Under the condition that the historical cached key is authentic, this reliably detects and rejects newly injected Man-in-the-Middle (MitM) attacks or ARP spoofing on the local segment.
3. **What Key Pinning Does NOT Guarantee:**
   - It does NOT constitute an independent hardware-level mathematical proof of silicon authenticity. If the historical connection was intercepted at the moment of first initialization, the cache would have preserved the interceptor's key.
   - Independent verification requires direct out-of-band physical extraction on the router (e.g. via UART or local console):
     ```sh
     dropbearkey -y -f /etc/dropbear/dropbear_rsa_host_key | ssh-keygen -l -f -
     ```
   - Until verified against physical storage or serial console, this key is classified as **`PINNED_HISTORICAL_CACHE`**, providing conditional session continuity protection rather than an absolute hardware root-of-trust.

---

## 3. Cryptographic Verification & Host Key Injection Protocol

Before opening an SSH connection to the router, all management and audit scripts MUST execute the following verification pipeline without invoking `ssh-keyscan`:

```sh
PINNED_KEY_FILE="${WORKSPACE_ROOT}/config/cr8818_host_key.pub"
EXPECTED_FINGERPRINT="SHA256:feZ+NfroyCIlYrC74Z1ZazUSby+WqxRxZM63Q6Q9HmM"

# Step 1: Verify the integrity of the pinned local public key file
ACTUAL_FINGERPRINT=$(ssh-keygen -l -f "$PINNED_KEY_FILE" 2>/dev/null | awk '{print $2}')
if [ "$ACTUAL_FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]; then
    echo "[SECURITY ERROR] Pinned host key fingerprint mismatch!" >&2
    echo "  Expected: $EXPECTED_FINGERPRINT" >&2
    echo "  Actual:   $ACTUAL_FINGERPRINT" >&2
    exit 1
fi

# Step 2: Synthesize a dedicated known_hosts file using the pinned key
KNOWN_HOSTS_DIR="$(mktemp -d /tmp/ssh_pinned.XXXXXX)"
KNOWN_HOSTS_FILE="${KNOWN_HOSTS_DIR}/known_hosts"
trap 'rm -rf "$KNOWN_HOSTS_DIR"' EXIT

PUB_KEY_DATA=$(awk '{print $1, $2}' "$PINNED_KEY_FILE")
echo "[$ROUTER_IP]:$ROUTER_PORT $PUB_KEY_DATA" > "$KNOWN_HOSTS_FILE"
chmod 600 "$KNOWN_HOSTS_FILE"

# Step 3: Execute SSH with strict host key checking against the pinned file ONLY
sshpass -e ssh -p "$ROUTER_PORT" \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$KNOWN_HOSTS_FILE" \
  -o GlobalKnownHostsFile=/dev/null \
  -o CheckHostIP=no \
  -o HostKeyAlgorithms=+ssh-rsa \
  -o PubkeyAcceptedKeyTypes=+ssh-rsa \
  -o ConnectTimeout=5 \
  "${ROUTER_USER}@${ROUTER_IP}" "$COMMAND"
```

### Security Properties:
1. **Zero Network Trust:** No keys are downloaded dynamically over the network.
2. **Conditional MitM Protection:** If an ARP-spoofing or DNS/IP hijack is attempted, SSH immediately terminates because the server's presented host key will not match the pinned public key (conditional upon historical cache authenticity).
3. **No Secret Leakage:** Only public key cryptographic hashes are committed. No router passwords or private keys are stored in Git.
