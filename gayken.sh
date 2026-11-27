#!/usr/bin/env bash
#
# gayken.sh
# DDBox - Offline E2EE Key Generator
#
# Generates a cryptographically secure 256-bit (64-hex) key for
# DDBox's Offline E2EE Mode.
#
set -euo pipefail

# Standard ANSI colors (safe for mobile copy-paste)
GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE} DDBox Offline Key Generator ${NC}"
echo -e "${BLUE}==================================================${NC}"

# Check Dependencies
if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${RED}[X] python3 is not installed. Please install it first.${NC}"
    exit 1
fi

# Generate 32 random bytes (256 bits) and encode as 64 hex characters using Python's secrets module
KEY=$(python3 -c 'import secrets; print(secrets.token_hex(32))')

if [[ ${#KEY} -ne 64 ]]; then
    echo -e "${RED}[X] Error: generated key is not 64 hex characters.${NC}"
    exit 1
fi

echo -e "${GREEN}[+] Generated 256-bit (64-hex) key:${NC}"
echo ""
echo -e "    ${WHITE}${GREEN}${KEY}${NC}"
echo ""
echo -e "${BLUE}--------------------------------------------------${NC}"
echo -e "${YELLOW}[!] INSTRUCTIONS:${NC} Copy the key above."
echo -e "    When you open DDBox in your browser, paste this key into the"
echo -e "    ${WHITE}Offline E2EE Key Mode${NC} prompt to unlock the room."
echo -e "    Do not share this key over insecure channels."
echo -e "${BLUE}--------------------------------------------------${NC}"
echo ""