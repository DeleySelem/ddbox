# DDBox

**DDBox** is a secure, decentralized, end-to-end encrypted (E2EE) communication platform designed for ephemeral, high-security environments and deaddrop-style communication. 

## 🛡️ Security Architecture & Standards

DDBox is engineered to withstand modern cryptographic threats, including those posed by quantum computing. It utilizes **Post-Quantum Cryptography (PQC)** alongside classical symmetric encryption, aligning with **NSA CNSA 2.0** and U.S. Army standards for National Security Systems (NSS).

### Protocol Stack
- **Asymmetric Key Exchange:** `fips203` (ML-KEM / formerly CRYSTALS-Kyber)
- **Symmetric Encryption:** AES-256-GCM (256-bit keys)
- **Data Integrity / Hashing:** **SHA-256** (via `cryptography>=48`)

### Comparison to U.S. Government Standards

| Feature | DDBox Implementation | NSA / U.S. Army Standard | Compliance / Status |
| :--- | :--- | :--- | :--- |
| **PQC Key Encapsulation** | **ML-KEM (FIPS 203)** | **CNSA 2.0** | **Fully Compliant.** NSA mandates ML-KEM for all National Security Systems by 2030 to prevent "Harvest Now, Decrypt Later" attacks. |
| **Symmetric Encryption** | **AES-256-GCM** | **AES-256** | **Compliant.** AES-256 is the standard for TOP SECRET information. GCM provides authenticated encryption. |
| **Cryptographic Hashing** | **SHA-256** | **SHA-384 or SHA-512** | **⚠️ Partial Compliance.** CNSA 2.0 mandates SHA-384/512. SHA-256 is currently used in `main.py` for PBKDF2HMAC and HKDF. |
| **Digital Signatures (PQC)** | **ML-DSA-87 (FIPS 204)** | **ML-DSA-87** | **Compliant.** The NSA approves ML-DSA-87 for quantum-resistant signatures. |
| **Offline Key Generation** | **256-bit (64-hex) CSPRNG** | **NIST SP 800-90A** | **Compliant.** Keys are generated locally using `openssl rand`, never transmitted over the network. |

---

## 🚀 Automated Installation (Android / Termux)

Because Android's standard environment restricts complex Python builds (specifically the Rust requirements for Post-Quantum libraries), DDBox utilizes `proot-distro` to run a full Debian Linux environment inside Termux. 

The repository includes **three automated installation scripts** to make this process seamless.

### Step 1: Install Termux
1. Search the internet for **F-Droid**.
2. Install F-Droid and grant required permissions.
3. Open F-Droid, search for **Termux**, and install it.
   > ⚠️ **WARNING:** Do **NOT** use the Google Play Store version of Termux. It is deprecated and contains surveillance backdoors.
4. Open Termux.

### Step 2: Bootstrap Environment (`autoinstall_1.sh`)
Copy and paste the following block into Termux. This will install Git, clone the repository, and run the autoinstallers.

```bash
pkg update -y && pkg upgrade -y && pkg install -y git proot-distro
git clone https://github.com/DeleySelem/ddbox
cd ddbox
bash autoinstall_1.sh
```

This will create 'ddbox' folder in Termux terminal from which it only runs autoinstaller_1.sh to install proot-distro debian, login debian and clone the working ddbox folder and dependencies inside the Debian. You can delete the ddbox folder from Termux files after installatiln is done.

### If autoinstall fails (it currently does!)

Follow the on-screen instructions. Once Debian is installed, log into it:

```bash
proot-distro login debian
```

Step 3: System Setup (autoinstall_2.sh)

Now that you are inside Debian (root@localhost:~#), clone the repository again inside the Debian environment and run the second autoinstaller. This installs system build tools, Rust, and ngrok.

```bash
apt update && apt install -y git
git clone https://github.com/DeleySelem/ddbox
cd ddbox
bash autoinstall_2.sh
```

Note: During this step, you will be prompted to paste your ngrok Auth Token. Get it from dashboard.ngrok.com.

Step 4: Crypto Setup & Launch (autoinstall_3.sh)

Run the final autoinstaller. This script will run the official setup.sh, compile the Post-Quantum dependencies (fips203 and cryptography), and prompt you to launch the server.

```bash
bash autoinstall_3.sh
```

Step 5: Generate Offline Keys

Before or during the launch, you must generate your E2EE key. Open a new Termux session (or exit the server temporarily) and run:

```bash
bash gayken.sh
```

Copy the printed 64-character hex key and save it securely. You will paste this into the DDBox web interface to decrypt the room.

Step 6: Connect

1. Wait for ngrok to output a URL looking like: https://xxxx-xxx-xxx-xxx-xx.ngrok-free.app where x is number/letter.
2. If the ngrok warning page appears, click "Visit Site" (this only happens on the free tier).
3. Paste your Offline Key into the DDBox UI.
4. Keep both the Termux terminal and your browser open to prevent connection drops.

---

💻 Manual Installation (Desktop Linux / macOS)

1. Ensure you have Python 3.10+, Rust, and Cargo installed.
2. Clone the repository:
   ```bash
   git clone https://github.com/DeleySelem/ddbox
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
4. Audit your traffic: Free ngrok tunnels show a warning page. Do not use free ngrok for operational deployments where stealth is required.
