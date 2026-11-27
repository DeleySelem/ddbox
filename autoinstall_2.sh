#!/usr/bin/env bash
# autoinstall_2.sh - Part 2 (Run inside ~/ddbox in Debian)
set -uo pipefail                                           
RST=$'\033[0m'; B=$'\033[1m'; C_LGRAY=$'\033[38;2;190;190;190m'; C_WHITE=$'\033[1;38;2;255;255;255m'; C_DIM=$'\033[2;38;2;150;150;150m'; C_RED=$'\033[1;38;2;255;60;60m'         heat() {
  awk -v text="$1" -v stops="0;120;255 0;220;220 255;220;0 255;60;60" '
    BEGIN {
      n = split(stops, arr, " "); len = length(text);            for (i = 0; i < len; i++) {
        ch = substr(text, i+1, 1); pos = (len > 1) ? i / (len - 1) : 0;
        seg = pos * (n - 1); idx = int(seg); if (idx >= n - 1) idx = n - 2;                                                   frac = seg - idx; split(arr[idx+1], a, ";"); split(arr[idx+2], b, ";");
        r = a[1]+(b[1]-a[1])*frac; g = a[2]+(b[2]-a[2])*frac; bl = a[3]+(b[3]-a[3])*frac;
        printf "\033[1;38;2;%d;%d;%dm%s", r, g, bl, ch;
      }
      printf "\033[0m\n";
    }'
}
hr() { printf " ${C_DIM}%s${RST}\n" "$(printf '─%.0s' $(seq 1 60))"; }
title() { echo; printf " ${B}▸ "; heat "$1"; hr; }

if [[ ! -f "autoinstall_3.sh" ]]; then
    echo -e "${C_RED}ERROR: You must run this script from the root of the ddbox repository.${RST}"
    exit 1
fi

# ── System Dependencies ─────────────────────────────────────────────────────
title "Installing System Dependencies"
printf " ${C_WHITE}→${RST} ${C_LGRAY}Updating APT and installing build tools (rust, ssl, ffi)...${RST}\n"
apt update && apt upgrade -y
apt install -y git curl unzip wget build-essential libssl-dev libffi-dev rustc cargo python3-pip python3-venv

# ── Install ngrok (ARM64) ───────────────────────────────────────────────────
title "Installing ngrok (ARM64)"
if ! command -v ngrok >/dev/null 2>&1; then
    printf " ${C_WHITE}→${RST} ${C_LGRAY}Downloading ngrok binary for Android (ARM64)...${RST}\n"
    curl -fsSL https://bin.ngrok.com/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.zip -o ngrok.zip
    unzip -o ngrok.zip -d /usr/local/bin/
    chmod +x /usr/local/bin/ngrok
    rm ngrok.zip
    printf " ${C_WHITE}✓${RST} ${C_LGRAY}ngrok installed successfully.${RST}\n"
else
    printf " ${C_WHITE}✓${RST} ${C_LGRAY}ngrok is already installed.${RST}\n"
fi

# ── ngrok Auth Token ────────────────────────────────────────────────────────
title "ngrok Authentication"
cat <<EOF
To get your token:
1. Open browser: ngrok.com
2. Login -> Open tab Quickstart
3. For Android select: 'ARM64, aarch64...'
4. Click 'Show auth-token' and copy it.
EOF

echo
read -p "Paste your ngrok auth-token here: " NGROK_TOKEN
if [[ -n "$NGROK_TOKEN" ]]; then
    ngrok config add-authtoken "$NGROK_TOKEN"
    printf " ${C_WHITE}✓${RST} ${C_LGRAY}Auth token saved.${RST}\n"
else
    printf " ${C_RED}⚠ No token entered. You will need to run: ngrok config add-authtoken <TOKEN>${RST}\n"
fi

# ── Next Steps ──────────────────────────────────────────────────────────────
title "Next Step: Run Part 3"
cat <<EOF

System environment is ready! To finish installation and launch, run:

  bash autoinstall_3.sh

EOF