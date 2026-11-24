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
Contact
Author / maintainer contact: deleyselem@proton.me.