#!/usr/bin/env bash
#
# generate_ddbox_key.sh
#
# Generates a 256-bit (64-hex) Offline E2EE key for DDBox.
# Run this BEFORE starting the DDBox server / ngrok tunnel.
# Paste the generated key into the DDBox UI when prompted.
#
set -euo pipefail

KEY=$(openssl rand -hex 32)

if [[ ${#KEY} -ne 64 ]]; then
    echo "Error: generated key is not 64 hex characters." >&2
    exit 1
fi

echo "DDBox Offline E2EE Key (256-bit / 64-hex):"
echo
echo "  ${KEY}"
echo
echo "Keep this key secret. Share it with participants through a secure out-of-band channel."