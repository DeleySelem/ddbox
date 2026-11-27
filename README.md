# DDBox

**DDBox** is a secure, decentralized, end-to-end encrypted (E2EE) communication platform designed for ephemeral, high-security environments for deaddrop -style communication. 

## 🛡️ Security Architecture & Standards

DDBox is built to withstand modern cryptographic threats, including those posed by quantum computing. It utilizes **Post-Quantum Cryptography (PQC)** alongside classical symmetric encryption, strictly aligning with the **NSA's CNSA 2.0** (Commercial National Security Algorithm Suite) guidance and U.S. Army standards for National Security Systems (NSS).

### Protocol Stack
- **Asymmetric Key Exchange:** `fips203` (ML-KEM / formerly CRYSTALS-Kyber)
- **Symmetric Encryption:** AES-256-GCM (256-bit keys)
- **Data Integrity / Hashing:** **SHA-512** (via `cryptography>=48`)

### Comparison to U.S. Government Standards

| Feature | DDBox Implementation | NSA / U.S. Army Standard | Compliance / Status |
| :--- | :--- | :--- | :--- |
| **PQC Key Encapsulation** | **ML-KEM (FIPS 203)** | **CNSA 2.0** | **Fully Compliant.** The NSA mandates ML-KEM for all National Security Systems (NSS) transitioning to quantum-resistant algorithms by 2030 to prevent "Harvest Now, Decrypt Later" attacks. |
| **Symmetric Encryption** | **AES-256-GCM** | **AES-256** | **Compliant.** AES-256 is the standard for TOP SECRET information. GCM provides authenticated encryption, preventing tampering. |
| **Cryptographic Hashing** | **SHA-512** | **SHA-384 or SHA-512** | **Compliant.** CNSA 2.0 mandates SHA-384 or SHA-512 (FIPS 180-4) for hashing. SHA-256 is explicitly disallowed due to insufficient collision resistance for NSS. |
| **Digital Signatures (PQC)** | **ML-DSA-87 (FIPS 204)** | **ML-DSA-87** | **Compliant.** The NSA approves ML-DSA-87. Pre-hashing for signatures is backed by SHA-512. |
| **Offline Key Generation** | **256-bit (64-hex) CSPRNG** | **NIST SP 800-90A** | **Compliant.** Keys are generated locally using `openssl rand` (SHA-512 backed), never transmitted over the network. |

> **Note:** DDBox's use of ML-KEM via the `fips203` Python library ensures that even if an adversary records traffic today, they cannot decrypt it with a future quantum computer.

---

## 🚀 Automated Installation (Android / Termux)

Because Android's standard environment restricts complex Python builds (specifically the Rust requirements for Post-Quantum libraries), DDBox uses `proot-distro` to run a full Debian Linux environment inside Termux.

### Step 1: Install Termux
1. Search the internet for **F-Droid**.
2. Install F-Droid and grant required permissions.
3. Open F-Droid, search for **Termux**, and install it.
   > ⚠️ **WARNING:** Do **NOT** use the Google Play Store version of Termux. It is deprecated, broken, and contains surveillance backdoors.
4. Open Termux.

### Step 2: Bootstrap Debian
Copy and paste the following command into Termux. This updates Termux, installs `proot-distro`, downloads Debian, and logs you into the Debian environment:

```bash
pkg update -y && pkg upgrade -y && pkg install -y proot-distro
proot-distro install debian
proot-distro login debian
```

Step 3: Clone and Install Part 1 (Inside Debian)

Once you are logged into Debian (your prompt will change to root@localhost:~#), copy and paste this entire block:

```bash
apt update && apt install -y git
git clone https://github.com/deleyselem/ddbox
cd ddbox
bash autoinstall_2.sh
```

Note: autoinstall_2.sh will install Rust, build tools, the ngrok binary (ARM64), and prompt you for your ngrok Auth Token (get it from ngrok.com).

Step 4: Finish Setup

After autoinstall_2.sh completes, run the final setup script to compile the cryptography dependencies and launch options:

```bash
bash autoinstall_3.sh
```

Step 5: Generate Offline Keys

Before starting the server, generate your E2EE key. Run:

```bash
bash gayken.sh
```

Copy the printed 64-character hex key and save it securely. You will need to paste this into the DDBox web interface.

Step 6: Launch the Server

Start the Flask server and ngrok tunnel:

```bash
python3 main.py | ngrok http 5000
```

1. Wait for ngrok to output a URL ending in https://xxxx-xxx-xxx-xxx-xx.ngrok-free.app.
2. If the ngrok warning page appears, click "Visit Site" (this only happens on the free tier).
3. Paste your Offline Key into the UI to decrypt the room.
4. Keep both the Termux terminal and your browser open to prevent connection drops.

---

💻 Manual Installation (Desktop Linux / macOS)

1. Ensure you have Python 3.10+, Rust, and Cargo installed.
2. Clone the repository:
   ```bash
   git clone https://github.com/deleyselem/ddbox
   cd ddbox
   ```
3. Run the setup:
   ```bash
   bash setup.sh
   ```
4. Install Post-Quantum Dependencies:
   ```bash
   pip install --upgrade "cryptography>=48" fips203
   ```
5. Generate Keys & Launch:
   ```bash
   bash gayken.sh
   python3 main.py
   ```

---

🔒 Operational Security Rules

1. Never share your Offline Key over the same channel you are using to communicate.
2. Keep the Termux terminal open while the server is running. Android may kill background processes to save battery.
3. Do not use sudo inside the proot-distro Debian environment. You are already the root user, and sudo is not installed by default.
4. Use ML-KEM rotation for long-lived sessions if you are transmitting highly sensitive data.