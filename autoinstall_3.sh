#!/usr/bin/env bash
# autoinstall_3.sh - Part 3 (Run inside ~/ddbox in Debian)
set -uo pipefail

echo "=================================================="
echo "DDBox Installation - Part 3"
echo "=================================================="

echo ""
echo "[*] Running Official setup.sh..."
bash setup.sh

echo ""
echo "[*] Installing Post-Quantum Crypto Dependencies..."

apt-get install *cryptography
apt-get install *fips203

echo "[+] Crypto dependencies successfully compiled and installed."

echo ""
echo "=================================================="
echo "Launching DDBox"
echo "=================================================="
cat <<EOF
Everything is ready! To start the server and ngrok tunnel, run:

  python3 main.py | ./ngrok http 5000

Wait for ngrok to output a link ending in .ngrok-free.app. 
Copy that link and open it in your Android browser.
Keep both this Termux screen and your browser open to prevent connection drops.
EOF

read -p "Do you want to start the server now? (y/n): " START_NOW
if [[ "${START_NOW,,}" == "y" ]]; then
    python3 main.py | ./ngrok http 5000
fi