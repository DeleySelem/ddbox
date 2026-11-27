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
C_RED=$'\033[1;38;2;255;60;60m'

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

# ── Check Dependencies ──────────────────────────────────────────────────────
title "DDBox Offline Key Generator"

if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${C_RED}✗ python3 is not installed. Please install it first.${RST}"
    exit 1
fi

# Generate 32 random bytes (256 bits) and encode as 64 hex characters using Python's secrets module
KEY=$(python3 -c 'import secrets; print(secrets.token_hex(32))')

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