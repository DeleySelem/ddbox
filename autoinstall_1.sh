#!/usr/bin/env bash
# autoinstall.sh - Part 1 (Run in Termux to install Debian)
set -uo pipefail

# Standard ANSI colors (safe for mobile copy-paste)
GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE} DDBox --- autoinstallation wizard ${NC}"
echo -e "${BLUE}==================================================${NC}"

cat <<EOF
Author: D373Y 5373M
Version: 1.0.6.

Step-by-step instructions:
1. Search from internet: 'F-droid'
2. Install F-droid + grant needed permissions
3. Open F-droid search for 'termux'
4. IMPORTANT: Install Termux only from F-droid. Do NOT use Android Playstore termux (has surveillance backdoors).
5. Open termux (You are here!)
EOF

echo ""
echo -e "${CYAN}=== Installing proot-distro and Debian ===${NC}"
echo -e "[*] Updating Termux packages..."
pkg update -y && pkg upgrade -y
pkg install -y proot-distro

# Check if Debian is already installed
if ! proot-distro list 2>/dev/null | grep -qi '^debian'; then
    echo -e "[*] Installing Debian rootfs..."
    proot-distro install debian
else
    echo -e "${GREEN}[+] Debian is already installed.${NC}"
fi

echo ""
echo -e "${CYAN}=== Next Step: Login to Debian and Clone DDBox ===${NC}"
cat <<EOF

If autoinstallation fails to login Debian: 

You must now log into Debian. Copy and paste this exact command:

  proot-distro login debian

Once your prompt changes to ${RED}root@localhost:~#${NC}, run this block:

  apt update && apt install -y git
  git clone https://github.com/deleyselem/ddbox
  cd ddbox
  bash autoinstall_2.sh

EOF
echo "DDBox --- Autoinstallation continues..."
echo ""
proot-distro login debian -- bash -c "apt update && apt install -y git && git clone https://github.com/DeleySelem/ddbox && cd ddbox && bash autoinstall_2.sh"