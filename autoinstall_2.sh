#!/usr/bin/env bash
# autoinstall_2.sh - Part 2 (Run inside ~/ddbox in Debian)
set -uo pipefail

# Standard ANSI colors (no complex formatting, safe for mobile copy-paste)
GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE} DDBox Installation - Part 2 ${NC}"
echo -e "${BLUE}==================================================${NC}"

if [[ ! -f "autoinstall_3.sh" ]]; then
    echo -e "${RED}ERROR: You must run this script from the root of the ddbox repository.${NC}"
    exit 1
fi

# System Dependencies
echo -e "\n${CYAN}[*] Updating APT and installing build tools (rust, ssl, ffi)...${NC}"
apt update && apt upgrade -y
apt install -y git curl unzip wget build-essential libssl-dev libffi-dev rustc cargo python3-pip python3-venv

# Install ngrok
echo -e "\n${CYAN}[*] Installing ngrok...${NC}"
if ! command -v ngrok >/dev/null 2>&1; then
    echo -e "Downloading ngrok..."
    curl -fsSL https://bin.ngrok.com/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz | tar -xz

    echo -e "${GREEN}[+] ngrok installed successfully.${NC}"
else
    echo -e "${GREEN}[+] ngrok is already installed.${NC}"
fi

# ngrok Auth Token
echo -e "\n${CYAN}=== ngrok Authentication ===${NC}"
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
    ./ngrok authtoken "$NGROK_TOKEN"
    echo -e "${GREEN}[+] Auth token saved.${NC}"
else
    echo -e "${YELLOW}[!] No token entered. You will need to run: ngrok config add-authtoken or ./ngrok authtoken <TOKEN>${NC}"
fi

# Next Steps
echo -e "\n${CYAN}=== Next Step: Run Part 3 ===${NC}"
echo -e "System environment is ready! To finish installation and launch, run:\n"
echo -e "Running:  ${YELLOW}bash autoinstall_3.sh${NC}\n"
bash autoinstall_3.sh