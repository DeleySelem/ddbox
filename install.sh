#!/usr/bin/env bash
# install.sh — DDBox unified installer
#   Termux (no arg) : bootstrap proot-distro Debian + install `ddbox` launcher
#   Debian  -2      : system deps, ngrok, ngrok token → hands off to -3
#   Debian  -3      : run setup.sh, verify crypto, generate offline key
#
# Author: D373Y 5373M  |  Version 1.1.0
set -uo pipefail

# ─────────────────────────────────────────────────────────────
#  Colors / helpers
# ─────────────────────────────────────────────────────────────
RST=$'\033[0m'; B=$'\033[1m'
C_RED=$'\033[1;38;2;255;60;60m'
C_LGRAY=$'\033[38;2;190;190;190m'
C_BLUE=$'\033[1;38;2;80;140;255m'
C_WHITE=$'\033[1;38;2;255;255;255m'
C_DIM=$'\033[2;38;2;150;150;150m'
C_GREEN=$'\033[1;38;2;120;220;120m'

ok()   { printf "  ${C_WHITE}[+]${RST}  ${C_LGRAY}%s${RST}\n" "$*"; }
info() { printf "  ${C_BLUE}[*]${RST}  ${C_LGRAY}%s${RST}\n" "$*"; }
warn() { printf "  ${C_RED}[!]${RST}  ${C_LGRAY}%s${RST}\n" "$*"; }
err()  { printf "  ${C_RED}[X]${RST}  ${C_RED}%s${RST}\n" "$*"; }

# ─────────────────────────────────────────────────────────────
#  Rainbow gradient (setup.sh style) — used for all titles
# ─────────────────────────────────────────────────────────────
heat() {
  awk -v text="$1" -v stops="0;120;255 0;220;220 255;220;0 255;60;60" '
    BEGIN {
      n = split(stops, arr, " ");
      len = length(text);
      for (i = 0; i < len; i++) {
        ch = substr(text, i+1, 1);
        pos = (len > 1) ? i / (len - 1) : 0;
        seg = pos * (n - 1);
        idx = int(seg);
        if (idx >= n - 1) idx = n - 2;
        frac = seg - idx;
        split(arr[idx+1], a, ";");
        split(arr[idx+2], b, ";");
        r  = a[1] + (b[1] - a[1]) * frac;
        g  = a[2] + (b[2] - a[2]) * frac;
        bl = a[3] + (b[3] - a[3]) * frac;
        printf "\033[1;38;2;%d;%d;%dm%s", r, g, bl, ch;
      }
      printf "\033[0m\n";
    }'
}

banner()     { printf '  '; heat "$1"; }
step_title() { printf '\n  '; heat "▶ $1"; }

CURRENT_STEP=0
TOTAL_STEPS=1
step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    step_title "[$CURRENT_STEP/$TOTAL_STEPS] $1"
}

# ─────────────────────────────────────────────────────────────
#  Termux side
# ─────────────────────────────────────────────────────────────
run_termux() {
    TOTAL_STEPS=6; CURRENT_STEP=0
    echo
    banner "D D B o x --- i n s t a l l"
    printf "  ${C_DIM}Author: D373Y 5373M   Version 1.1.0${RST}\n"

    step "Updating Termux packages"
    pkg update -y && pkg upgrade -y || warn "pkg update/upgrade reported issues"

    step "Installing proot-distro"
    pkg install -y proot-distro || { err "proot-distro install failed"; exit 1; }

    step "Checking Debian rootfs"
    if proot-distro login debian -- true >/dev/null 2>&1; then
        ok "Debian already installed — proceeding"
    else
        info "Installing Debian rootfs (this can take a while)..."
        proot-distro install debian || { err "Debian install failed"; exit 1; }
        ok "Debian installed"
    fi

    step "Installing DDBox inside Debian"
    echo
    info "Entering Debian to clone repo and run install.sh -2..."
    echo
    # Clone repo inside Debian and run stage 2.
    # `rm -rf /root/ddbox` keeps this command idempotent on re-runs
    # (otherwise `git clone` fails when the directory already exists).
    if ! proot-distro login debian -- bash -c \
        "cd /root && rm -rf ddbox && apt update && apt install -y git && git clone https://github.com/DeleySelem/ddbox && cd ddbox && bash install.sh -2"; then
        err "Debian-side install failed"
        exit 1
    fi

    step "Creating systemwide 'ddbox' launcher"
    local DD="${PREFIX:-/data/data/com.termux/files/usr}/bin/ddbox"
    cat > "$DD" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# ddbox — launch DDBox inside proot-distro Debian (Python backend + ngrok tunnel)
exec proot-distro login debian -- bash -c 'cd /root/ddbox && python3 main.py | ./ngrok http 5000'
EOF
    chmod +x "$DD"
    ok "Installed launcher: $DD"

    step "Verifying launcher"
    if [ -x "$DD" ]; then ok "ddbox command ready"; else err "launcher missing"; exit 1; fi

    echo
    banner "D D B o x --- i n s t a l l  c o m p l e t e"
    printf "  ${C_LGRAY}Launch from anywhere:${RST}  ${C_WHITE}ddbox${RST}\n"
    printf "  ${C_DIM}First launch starts python + ngrok inside Debian.${RST}\n"
    echo
}

# ─────────────────────────────────────────────────────────────
#  Debian stage 2 — system deps + ngrok
# ─────────────────────────────────────────────────────────────
run_debian_stage2() {
    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
    APT_OPTS=(-y -o "Dpkg::Options::=--force-confold" -o "Dpkg::Options::=--force-confdef")
    TOTAL_STEPS=4; CURRENT_STEP=0
    echo
    banner "D D B o x --- d e b i a n  i n s t a l l"
    printf "  ${C_DIM}Author: D373Y 5373M   Version 1.1.0${RST}\n"

    if [ ! -f setup.sh ]; then
        err "setup.sh not found in $(pwd) — run this from /root/ddbox."
        exit 1
    fi

    step "Updating APT index"
    apt-get update "${APT_OPTS[@]}" || warn "apt-get update reported issues"

    step "Installing build tools, Rust, Python"
    apt-get install "${APT_OPTS[@]}" --no-install-recommends \
        git curl unzip wget ca-certificates \
        build-essential libssl-dev libffi-dev \
        rustc cargo python3-pip python3-venv \
        || { err "APT install failed"; exit 1; }
    ok "System packages installed"

    step "Installing ngrok (from ddbox folder)"
    if [ ! -x ./ngrok ]; then
        curl -fsSL https://bin.ngrok.com/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz | tar -xz \
            || { err "ngrok download failed"; exit 1; }
        chmod +x ./ngrok
        ok "ngrok installed: $(pwd)/ngrok"
    else
        ok "ngrok already present"
    fi

    step "Configuring ngrok auth token"
    if [ -f "$HOME/.config/ngrok/ngrok.yml" ] && grep -q '^authtoken:' "$HOME/.config/ngrok/ngrok.yml" 2>/dev/null; then
        ok "ngrok token already configured"
    else
        echo
        printf "  ${C_LGRAY}Get token at:${RST} ${C_BLUE}https://dashboard.ngrok.com/get-started/your-authtoken${RST}\n"
        printf "  ${C_WHITE}Paste ngrok auth token: ${RST}"
        read -r NGROK_TOKEN || NGROK_TOKEN=""
        if [ -n "${NGROK_TOKEN:-}" ]; then
            ./ngrok authtoken "$NGROK_TOKEN" && ok "ngrok token saved" || warn "ngrok authtoken failed"
        else
            warn "No token entered — you can run: ./ngrok authtoken <TOKEN> later"
        fi
    fi

    echo
    info "Stage 2 complete — handing off to install.sh -3..."
    exec bash "$0" -3
}

# ─────────────────────────────────────────────────────────────
#  Debian stage 3 — setup.sh + verify
# ─────────────────────────────────────────────────────────────
run_debian_stage3() {
    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
    TOTAL_STEPS=3; CURRENT_STEP=0
    echo
    banner "D D B o x --- d e b i a n  i n s t a l l (3 of 3)"
    printf "  ${C_DIM}Author: D373Y 5373M   Version 1.1.0${RST}\n"

    if [ ! -f setup.sh ]; then
        err "setup.sh not found in $(pwd) — run this from /root/ddbox."
        exit 1
    fi

    step "Running setup.sh (pip: cryptography>=48, fips203)"
    bash setup.sh || { err "setup.sh failed"; exit 1; }

    step "Verifying runtime imports"
    if python3 - <<'PY'
import sys
for m in ("flask", "flask_socketio", "cryptography"):
    try: __import__(m)
    except ImportError: print("missing:", m); sys.exit(1)
from cryptography.hazmat.primitives.asymmetric import mldsa  # noqa: F401
import fips203  # noqa: F401
PY
    then ok "All runtime imports resolve"
    else err "Runtime import verification failed"; exit 1
    fi

    step "Generating offline E2EE key"
    if [ -f gayken.sh ]; then
        bash gayken.sh || warn "gayken.sh reported issues"
    else
        warn "gayken.sh not found — generate key from DDBox UI later"
    fi

    echo
    banner "D e b i a n  i n s t a l l  c o m p l e t e"
    printf "  ${C_DIM}Exit Debian, then run '${RST}${C_WHITE}ddbox${RST}${C_DIM}' from Termux to launch.${RST}\n"
    echo
}

# ─────────────────────────────────────────────────────────────
#  Dispatch
# ─────────────────────────────────────────────────────────────
ARG="${1:-}"
if [ -z "$ARG" ]; then
    if command -v pkg >/dev/null 2>&1 && [ -d /data/data/com.termux ]; then
        run_termux
    else
        err "install.sh without arguments is Termux-only."
        err "Inside Debian, use: bash install.sh -2   (or -3 to resume)"
        exit 1
    fi
else
    case "$ARG" in
        -2) run_debian_stage2 ;;
        -3) run_debian_stage3 ;;
        *)  err "Unknown option: $ARG"
            err "Usage: install.sh          (Termux bootstrap)"
            err "       install.sh -2       (Debian deps + ngrok)"
            err "       install.sh -3       (Debian setup.sh + verify)"
            exit 1
            ;;
    esac
fi