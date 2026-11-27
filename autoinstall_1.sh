#!/usr/bin/env bash
# autoinstall.sh - Part 1 (Run in Termux to install Debian)
set -uo pipefail

RST=$'\033[0m'; B=$'\033[1m'; C_LGRAY=$'\033[38;2;190;190;190m'; C_WHITE=$'\033[1;38;2;255;255;255m'; C_DIM=$'\033[2;38;2;150;150;150m'; C_RED=$'\033[1;38;2;255;60;60m'
heat() {                                                     awk -v text="$1" -v stops="0;120;255 0;220;220 255;220;0 255;60;60" '
    BEGIN {                                                      n = split(stops, arr, " "); len = length(text);
      for (i = 0; i < len; i++) {
        ch = substr(text, i+1, 1); pos = (len > 1) ? i / (len - 1) : 0;
        seg = pos * (n - 1); idx = int(seg); if (idx >= n - 1) idx = n - 2;
        frac = seg - idx; split(arr[idx+1], a, ";"); split(arr[idx+2], b, ";");
        r = a[1]+(b[1]-a[1])*frac; g = a[2]+(b[2]-a[2])*frac; bl = a[3]+(b[3]-a[3])*frac;
        printf "\033[1;38;2;%d;%d;%dm%s", r, g, bl, ch;
      }
      printf "\033[0m\n";
    }'
}
hr() { printf " ${C_DIM}%s${RST}\n" "$(printf '─%.0s' $(seq 1 60))"; }
title() { echo; printf " ${B}▸ "; heat "$1"; hr; }

# ── Wizard Instructions ─────────────────────────────────────────────────────
title "DDBox --- autoinstallation wizard"
cat <<EOF
Author: D373Y 5373M
Version: 1.0.5

Step-by-step instructions:
1. Search from internet: 'F-droid'
2. Install F-droid + grant needed permissions
3. Open F-droid search for 'termux'
4. IMPORTANT: Install Termux only from F-droid. Do NOT use Android Playstore termux (has surveillance backdoors).
5. Open termux (You are here!)
EOF

# ── Termux Setup ────────────────────────────────────────────────────────────
title "Installing proot-distro and Debian"
printf " ${C_WHITE}→${RST} ${C_LGRAY}Updating Termux packages...${RST}\n"
pkg update -y && pkg upgrade -y
pkg install -y proot-distro

if ! proot-distro list 2>/dev/null | grep -qi '^debian'; then
    printf " ${C_WHITE}→${RST} ${C_LGRAY}Installing Debian rootfs...${RST}\n"
    proot-distro install debian
else
    printf " ${C_WHITE}✓${RST} ${C_LGRAY}Debian is already installed.${RST}\n"
fi

# ── Next Steps ──────────────────────────────────────────────────────────────
title "Next Step: Login to Debian and Clone DDBox"
cat <<EOF

You must now log into Debian. Copy and paste this exact block:

  proot-distro login debian

Once your prompt changes to ${C_RED}root@localhost:~#${RST}, run this block:

  apt update && apt install -y git
  git clone https://github.com/deleyselem/ddbox
  cd ddbox
  bash autoinstall_2.sh

EOF