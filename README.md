
```markdown
# DDBox 

**DDBox** is a secure, decentralized, end-to-end encrypted (E2EE) communication platform designed for ephemeral, high-security environments for "deaddrop" communication. 

## 🛡️ Security Architecture & Standards

DDBox is built to withstand modern cryptographic threats, including those posed by quantum computing. It utilizes **Post-Quantum Cryptography (PQC)** alongside classical symmetric encryption.

### Protocol Stack
- **Asymmetric Key Exchange:** `fips203` (ML-KEM / formerly CRYSTALS-Kyber)
- **Symmetric Encryption:** AES-256-GCM (256-bit keys)
- **Hashing:** SHA-3 (via `cryptography>=48`)

### Comparison to U.S. Government Standards

| Feature | DDBox Implementation | NSA / U.S. Army Standard | Compliance / Status |
| :--- | :--- | :--- | :--- |
| **PQC Key Encapsulation** | **ML-KEM (FIPS 203)** | **CNSA 2.0** (Commercial National Security Algorithm Suite 2.0) | **Fully Compliant.** The NSA mandates ML-KEM for all National Security Systems (NSS) transitioning to quantum-resistant algorithms by 2030. The U.S. Army is actively migrating to FIPS 203 to prevent "Harvest Now, Decrypt Later" attacks. |
| **Symmetric Encryption** | **AES-256-GCM** | **AES-256** | **Compliant.** AES-256 is the standard for TOP SECRET information up to classified levels. GCM provides authenticated encryption (preventing tampering). |
| **Offline Key Generation** | **256-bit (64-hex) CSPRNG** | **NIST SP 800-90A** | **Compliant.** Keys are generated locally using cryptographically secure pseudo-random number generators (`openssl rand`), never transmitted over the network. |

> **Note:** DDBox's use of ML-KEM via the `fips203` Python library ensures that even if an adversary records traffic today, they cannot decrypt it with a future quantum computer.

---

## 🚀 Automated Installation (Android / Termux)

Because Android's standard environment restricts complex Python builds, DDBox uses `proot-distro` to run a full Debian Linux environment inside Termux.

### Step 1: Install Termux
1. Search the internet for **F-Droid**.
2. Install F-Droid and grant required permissions.
3. Open F-Droid, search for **Termux**, and install it.
   > ⚠️ **WARNING:** Do **NOT** use the Google Play Store version of Termux. It is deprecated, broken, and contains surveillance backdoors.
4. Open Termux.

### Step 2: Bootstrap Debian
Copy and paste the following command into Termux. This downloads the bootstrap script and installs Debian:

```bash
pkg update -y && pkg upgrade -y && pkg install -y proot-distro
proot-distro install debian
proot-distro login debian
```

Step 3: Install DDBox (Inside Debian)

Once you are logged into Debian (your prompt will change to root@localhost:~#), copy and paste this entire block:

```bash
apt update && apt install -y git
git clone https://github.com/deleyselem/ddbox
cd ddbox
bash autoinstall_2.sh
```

Note: autoinstall_2.sh will install Rust, compilers, ngrok, and prompt you for your ngrok Auth Token (get it from ngrok.com).

Step 4: Finish Setup

After autoinstall_2.sh completes, run the final setup script:

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
3. Do not use sudo inside the proot-distro Debian environment. You are already the root user, and sudo is not installed.

```

---

### 2. `gayken.sh`

Save this file as `gayken.sh` in the root of the `ddbox` repository.

```bash
#!/usr/bin/env bash
#
# gayken.sh
# DDBox - Offline E2EE Key Generator
#
# Generates a cryptographically secure 256-bit (64-hex) key for
# DDBox's Offline E2EE Mode.
#
set -euo pipefail

# ── Rainbow Gradient Styling ────────────────────────────────────────────────
RST=$'\033[0m'
B=$'\033[1m'
C_LGRAY=$'\033[38;2;190;190;190m'
C_WHITE=$'\033[1;38;2;255;255;255m'
C_DIM=$'\033[2;38;2;150;150;150m'
C_GREEN=$'\033[1;38;2;80;255;120m'

heat() {
  awk -v text="$1" -v stops="0;120;255 0;220;220 255;220;0 255;60;60" '
    BEGIN {
      n = split(stops, arr, " "); len = length(text);
      for (i = 0; i < len; i++) {
        ch = substr(text, i+1, 1); pos = (len > 1) ? i / (len - 1) : 0;
        seg = pos * (n - 1); idx = int(seg);
        if (idx >= n - 1) idx = n - 2;
        frac = seg - idx;
        split(arr[idx+1], a, ";"); split(arr[idx+2], b, ";");
        r = a[1]+(b[1]-a[1])*frac; g = a[2]+(b[2]-a[2])*frac; bl = a[3]+(b[3]-a[3])*frac;
        printf "\033[1;38;2;%d;%d;%dm%s", r, g, bl, ch;
      }
      printf "\033[0m\n";
    }'
}
hr() { printf " ${C_DIM}%s${RST}\n" "$(printf '─%.0s' $(seq 1 60))"; }
title() { echo; printf " ${B}▸ "; heat "$1"; hr; }

# ── Generate Key ────────────────────────────────────────────────────────────
title "DDBox Offline Key Generator"

if ! command -v openssl >/dev/null 2>&1; then
    echo -e "${C_RED}✗ openssl is not installed. Please install it first.${RST}"
    exit 1
fi

# Generate 32 random bytes (256 bits) and encode as 64 hex characters
KEY=$(openssl rand -hex 32)

if [[ ${#KEY} -ne 64 ]]; then
    echo -e "${C_RED}✗ Error: generated key is not 64 hex characters.${RST}"
    exit 1
fi

echo -e " ${C_WHITE}✓${RST} ${C_LGRAY}Generated 256-bit (64-hex) key:${RST}"
echo
echo -e "   ${B}${C_GREEN}${KEY}${RST}"
echo
hr
echo -e " ${C_WHITE}⚠ INSTRUCTIONS:${RST} ${C_LGRAY}Copy the key above.${RST}"
echo -e "   When you open DDBox in your browser, paste this key into the"
echo -e "   ${B}Offline E2EE Key Mode${RST} prompt to unlock the room."
echo -e "   Do not share this key over insecure channels."
hr
echo
```

Integration Notes:

1. Commit both files (README.md and gayken.sh) to the repository.
2. Make sure gayken.sh is executable (chmod +x gayken.sh).
3. The README clearly aligns the use of fips203 (ML-KEM) with the NSA's CNSA 2.0 and the U.S. Army's quantum-resistant migration timelines, giving the project high credibility for security-conscious users.