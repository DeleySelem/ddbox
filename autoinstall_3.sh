#!/usr/bin/env bash
# autoinstall_3.sh - Part 3 (Run inside ~/ddbox in Debian)
set -uo pipefail

RST=$'\033[0m'; B=$'\033[1m'; C_LGRAY=$'\033[38;2;190;190;190m'; C_WHITE=$'\033[1;38;2;255;255;255m'; C_DIM=$'\033[2;38;2;150;150;150m'; C_RED=$'\033[1;38;2;255;60;60m'
heat() {                                                     awk -v text="$1" -v stops="0;120;255 0;220;220 255;220;0 255;60;60" '
    BEGIN {                                                      n = split(stops, arr, " "); len = length(text);
      for (i = 0; i < len; i++) {
        ch = substr(text, i+1, 1); pos = (len > 1) ? i / (len - 1) : 0;                                                       seg = pos * (n - 1); idx = int(seg); if (idx >= n - 1) idx = n - 2;
        frac = seg - idx; split(arr[idx+1], a, ";"); split(arr[idx+2], b, ";");
        r = a[1]+(b[1]-a[1])*frac; g = a[2]+(b[2]-a[2])*frac; bl = a[3]+(b[3]-a[3])*frac;
        printf "\033[1;38;2;%d;%d;%dm%s", r, g, bl, ch;
      }
      printf "\033[0m\n";
    }'
}
hr() { printf " ${C_DIM}%s${RST}\n" "$(printf '─%.0s' $(seq 1 60))"; }
title() { echo; printf " ${B}▸ "; heat "$1"; hr; }

# ── Run Setup ───────────────────────────────────────────────────────────────
title "Running Official setup.sh"
bash setup.sh

# ── Fix Crypto Dependencies ─────────────────────────────────────────────────
# Applying the exact fixes from bash history for cryptography>=48 and fips203
title "Installing Post-Quantum Crypto Dependencies"
printf " ${C_WHITE}→${RST} ${C_LGRAY}Applying --break-system-packages flag for PEP 668...${RST}\n"

python3 -m pip install --upgrade --break-system-packages "cryptography>=48"
python3 -m pip install --upgrade --break-system-packages fips203

printf " ${C_WHITE}✓${RST} ${C_LGRAY}Crypto dependencies successfully compiled and installed.${RST}\n"

# ── Final Launch ────────────────────────────────────────────────────────────
title "Launching DDBox"
cat <<EOF
Everything is ready! To start the server and ngrok tunnel, run:

  python3 main.py | ngrok http 5000

Wait for ngrok to output a link ending in .ngrok-free.app.
Copy that link and open it in your Android browser.
Keep both this Termux screen and your browser open to prevent connection drops.
EOF

read -p "Do you want to start the server now? (y/n): " START_NOW
if [[ "${START_NOW,,}" == "y" ]]; then
    python3 main.py | ngrok http 5000
fi