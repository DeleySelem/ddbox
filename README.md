# DDBox

DDBox is a web-based encrypted chat application built with Flask, Flask-SocketIO (async_mode='threading'), and the Web Crypto API alongside post-quantum primitives. It uses ML-KEM-1024 (FIPS 203) for group key encapsulation, ML-DSA-87 (FIPS 204) for message signing, and AES-256-GCM for message encryption and /boot page delivery.

## Installation on Android (Termux + proot-distro Debian)

Running DDBox on Android via Termux and proot-distro (Debian) provides an apt and python3 environment isolated from Termux's native environment.
### 1. Set Up Termux and Install proot-distro
 ​
```bash
pkg update && pkg upgrade -y
pkg install -y proot-distro git
 ​
```

### 2. Install and Enter Debian
 ​
```bash
proot-distro install debian
proot-distro login debian
```

### Install System Packages Inside Debian

```bash
apt-get update && apt-get install -y
python3
python3-pip
python3-venv
python3-dev
build-essential
libffi-dev
git
```

If fips203 reports that libfips203.so is missing during verification, install libfips203-0 via apt-get if available, or build libfips203.so from integritychain/fips203 (ffi) with cargo / rustc and place it in /usr/local/lib (or set FIPS203_PYTHON_TESTING_LIBRARY).
 ​
### 4. Clone DDBox and Run setup.sh
 ​
```bash
git clone https://github.com/deleyselem/ddbox
cd ddbox
chmod +x setup.sh
bash setup.sh
```

setup.sh installs/upgrades flask, flask-socketio, cryptography>=48, and fips203, verifies eventlet is not installed (threading mode is used), and moves .html templates into templates/.
 ​
### 5. Start the Server
 ​
After installing and configuring ngrok:

```bash
python3 main.py | ngrok http 5000
```

The server listens on http://0.0.0.0:5000 (http://127.0.0.1:5000 locally).
 ​
## HTTPS & Public Access Notes

HTTPS for Secure Cookies: main.py sets SESSION_COOKIE_SECURE = True. Use an HTTPS tunnel or reverse proxy such as ngrok http 5000 when accessing over HTTPS or non-local hosts.
Keep Termux Active: Use a Termux wake lock (termux-wake-lock or the notification action) so Android does not suspend background hosting.
In-Memory State: Rooms, messages, keys, and rate limits live in memory and reset on restart.
 ​
## Cryptography & Security Caveats

ML-KEM-1024 (FIPS 203) & ML-DSA-87 (FIPS 204): Category 5 post-quantum key encapsulation and message envelope signing.
Server Trust Assumption: The server generates and holds group_key and page_passphrase in memory and delivers the /boot HTML blob. A compromised server can access in-memory secrets or alter served HTML, and software-only implementations do not provide FIPS 140-3 module validation or out-of-band identity verification. Always verify user fingerprints out-of-band.


## Security Protocols Map

DDBox combines post-quantum cryptography (**FIPS 203** and **FIPS 204**), **AES-256-GCM**, **HKDF / PBKDF2**, and an optional **Offline E2EE Key** mode so that messages remain encrypted on the client and—when offline E2EE is enabled—cannot be decrypted even if the server is compromised.

### 1. Protocol & Primitive Matrix

```text
| Layer / Function | Algorithm / Standard | Where It Runs | Purpose & Scope |
| :--- | :--- | :--- | :--- |
| **Post-Quantum KEM** | **ML-KEM-1024** (FIPS 203, Cat. 5) | Browser (`@noble/post-quantum`) + Server (`fips203.EncapsulationKey.encaps()`) | Encapsulates a shared secret to wrap/distribute the server-managed room group key when Offline E2EE mode is off. |
| **Post-Quantum Signatures** | **ML-DSA-87** (FIPS 204, Cat. 5) | Browser (`@noble/post-quantum` sign/verify) + Server (`cryptography>=48` `mldsa` verify) | Signs and verifies canonical JSON message envelopes (`room`, `sender`, `timestamp`, `ciphertext`) to prevent spoofing and tampering. |
| **Group Key Wrapping** | **HKDF-SHA256** + **AES-256-GCM** | Server (wrap) / Browser (unwrap via `SubtleCrypto`) | Derives a 256-bit wrapping key (`info: "ddbox-ml-kem-1024-group-key-wrap"`) from the ML-KEM-1024 shared secret and encrypts the room group key. |
| **Offline E2EE Key Mode** | **Client-Generated 256-bit (64-hex) Key** + **AES-256-GCM** | Browser only (out-of-band / offline exchange) | Host generates and shares the full key offline; recipients paste & apply it after joining. Server never receives or stores the key. |
| **Message Encryption** | **AES-256-GCM** (96-bit / 12-byte random IV) | Browser (`SubtleCrypto`) | Encrypts chat plaintext client-side before sending ciphertext over Socket.IO. |
| **Encrypted Page Delivery** | **PBKDF2-HMAC-SHA256** (100,000 iter.) + **AES-256-GCM** | Server (`cryptography`) $\rightarrow$ Browser (`/boot` + `/get_encrypted_page`) | Encrypts rendered `room.html` with a per-room passphrase before client-side decryption in `/boot`. |
| **Identity Fingerprints** | **SHA-256** (first 16 hex chars) | Browser (`SubtleCrypto.digest`) | Displays short fingerprints for ML-KEM-1024 encapsulation keys and ML-DSA-87 verification keys in the Users drawer. ||
```

### 2. End-to-End Protocol Flows

#### A. Standard Mode (ML-KEM-1024 Group Key + ML-DSA-87)

```text
Client                          Server
  |-- 1. Gen KEM-1024 & DSA-87 -->|
  |-- 2. Connect(ek, vk) -------->|
  |                               |-- 3. Encaps (ct, ss)
  |                               |-- 4. HKDF + AES wrap key
  |<-- 5. group_key (wrapped) ----|
  |-- 6. Decaps & unwrap key ---->|
  |-- 7. AES-GCM enc + DSA sign ->|
  |                               |-- 8. Verify DSA & relay
  |<-- 9. Verify DSA & decrypt ---|

#### B. Offline E2EE Key Mode (Out-of-Band Key)

```text
Host            Offline         Recipient         Server
  |-- 1. Check & Gen 64-hex ----->|                 |
  |                 |-- 2. Key -->|                 |
  |                               |-- 3. Join & apply key
  |-- 4. AES-GCM enc + DSA sign ------------------->|
  |                               |<-- 5. Cipher + sig
  |                               |-- 6. Verify & dec
```

## Contact
Author / maintainer contact: deleyselem@proton.me.