# DDBox

​DDBox is a web-based encrypted chat application built with Flask, Flask-SocketIO (async_mode='threading'), and the Web Crypto API. It uses ECDH (P-256) and AES-GCM for group messaging and delivers the chat room interface as an AES-GCM encrypted HTML blob decrypted client-side on /boot.

## Installation on Android (Termux + proot-distro Debian)

​Running DDBox on Android via Termux and proot-distro (Debian) gives you a standard apt and python3 environment while keeping the server isolated from Termux's native environment.

### 1. Set Up Termux and Install proot-distro

​Open Termux and update packages, then install proot-distro and git (optional if you clone inside Debian, or clone directly here):

pkg update && pkg upgrade -y
pkg install -y proot-distro git

### 2. Install and Enter Debian

​Install the Debian distribution and log into its shell:

proot-distro install debian
proot-distro login debian

### 3. Install System Packages Inside Debian

​Inside the Debian shell (root@localhost:~# or your user prompt), update apt and install Python 3, pip, git, and build/crypto dependencies (build-essential, libffi-dev, python3-dev) in case cryptography needs to build or link native libraries on ARM/AArch64:

apt-get update && apt-get install -y \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  build-essential \
  libffi-dev \
  git

### 4. Clone DDBox and Run setup.sh

​Clone the repository and run the included setup.sh script. It installs/updates flask, flask-socketio, and cryptography, ensures eventlet is not installed (since DDBox uses threading mode), and moves the .html templates (base.html, boot.html, home.html, room.html) into templates/:  

git clone https://github.com/deleyselem/ddbox
cd ddbox
chmod +x setup.sh
./setup.sh

Note on PEP 668 (externally-managed-environment): Modern Debian versions mark system Python as externally managed. setup.sh automatically falls back to --break-system-packages if needed, or you can create a virtual environment (python3 -m venv .venv && source .venv/bin/activate) before running setup.sh.

### 5. Start the Server

​Start DDBox inside the ddbox directory:

python3 main.py

The server listens on [http://0.0.0.0:5000](http://0.0.0.0:5000) ([http://127.0.0.1:5000](http://127.0.0.1:5000) locally).  
​HTTPS & Public Access (Important Notes)
​Secure Session Cookies: main.py sets SESSION_COOKIE_SECURE = True. Browsers will generally only send Secure cookies over HTTPS (or localhost / 127.0.0.1 depending on browser policy). If you access DDBox from another device on your LAN or over the internet, use an HTTPS reverse proxy or tunnel such as ngrok (ngrok http 5000) or Cloudflare Tunnel.

​Keeping Termux Alive: Android may suspend background Termux sessions. In Termux (outside proot-distro), tap Acquire wake lock in the Termux notification drawer or run termux-wake-lock to prevent background throttling while hosting.
​Ephemeral State: Rooms, messages, keys, and rate-limit counters are stored in memory in main.py and reset when the server restarts.
  
##​ Architecture & Cryptography Overview

​Backend: Flask + Flask-SocketIO (async_mode='threading') + cryptography.  
​Frontend: Vanilla JavaScript using the browser's Web Crypto API (crypto.subtle).  
​Encrypted Page Delivery: /boot fetches /get_encrypted_page, derives a 256-bit AES-GCM key via PBKDF2-HMAC-SHA256 (100,000 iterations) from the room's page_passphrase and salt, decrypts the rendered room.html in memory, and writes it to the document.

​Group Key Distribution & Rotation: Each client generates an ephemeral ECDH (P-256) key pair on room entry. The server encrypts the room's 32-byte AES-GCM group key using an ECDH shared secret + HKDF-SHA256 ("group-key-encryption") and rotates the group key every 5 minutes (300 seconds) while active members are present.  
​Message Encryption & History: Messages are encrypted client-side with AES-GCM (12-byte random IV prepended to ciphertext, base64-encoded). The server assigns monotonic message IDs, stores message objects in memory, supports incremental history sync (request_history with since_id), and exposes /logs/<room> to authenticated room members.  
​Security Considerations
​Server Trust Model: The server generates and holds the room's group_key and page_passphrase in memory. A compromised or malicious server can decrypt messages, log plaintexts, or view /logs/<room>.

​No Forward Secrecy or Message Signatures: Group keys rotate every 5 minutes rather than per message, and messages are encrypted with a shared group key without per-message sender signatures or out-of-band key verification.  
​Basic Identity & Rate Limits: Display names are stored in the Flask session without cryptographic identity verification, and rate limits are basic in-memory per-IP and per-(room, name) checks.
  
## Contact & Contributing

​Author / maintainer contact listed in the project documentation: deleyselem@proton.me.  