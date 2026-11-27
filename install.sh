#!/usr/bin/env bash
# install.sh — unified DDBox installer
#
# Stages (all in this one file):
#   Termux  (no args) : bootstrap Debian + run full install via proot-distro + launch
#   Debian  -2        : system deps + Rust + Python + ngrok + token  → chains to -3
#   Debian  -3        : setup.sh logic (pip, templates, verify) + key generation
#   Debian  -key      : regenerate offline E2EE key only
#   Debian  -launch   : start DDBox (python3 main.py | ./ngrok http 5000)
#
# Author: D373Y 5373M  |  Version 1.2.0
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
#  Rainbow gradient titles (setup.sh style)
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
#  Host detection — /etc/debian_version only exists inside Debian
# ─────────────────────────────────────────────────────────────
is_termux_host() {
    [ ! -f /etc/debian_version ] && command -v pkg >/dev/null 2>&1
}

# ─────────────────────────────────────────────────────────────
#  Debian stage -2 : system deps + ngrok
# ─────────────────────────────────────────────────────────────
run_debian_deps() {
    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
    APT_OPTS=(-y -o "Dpkg::Options::=--force-confold" -o "Dpkg::Options::=--force-confdef")
    TOTAL_STEPS=4; CURRENT_STEP=0
    echo
    banner "DDBox  ──  Debian install (1 of 2)"
    printf "  ${C_DIM}Author: D373Y 5373M   Version 1.2.0${RST}\n"

    if [ ! -f install.sh ]; then
        err "install.sh not found in $(pwd) — run from /root/ddbox."
        exit 1
    fi

    step "Updating APT index"
    apt-get update "${APT_OPTS[@]}" || warn "apt-get update reported issues"

    step "Installing build tools, Rust, Python"
    apt-get install "${APT_OPTS[@]}" --no-install-recommends \
        git curl unzip wget ca-certificates \
        build-essential libssl-dev libffi-dev \
        rustc cargo python3 python3-pip python3-venv \
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
#  Debian stage -3 : setup.sh logic + key generation
#  (port of setup.sh: python, pip, eventlet, packages, templates, verify)
# ─────────────────────────────────────────────────────────────
run_debian_setup() {
    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
    TOTAL_STEPS=5; CURRENT_STEP=0
    echo
    banner "DDBox  ──  Debian install (2 of 2)"
    printf "  ${C_DIM}Author: D373Y 5373M   Version 1.2.0${RST}\n"

    if [ ! -f main.py ]; then
        err "main.py not found in $(pwd) — run from /root/ddbox."
        exit 1
    fi

    step "Verifying Python & pip"
    command -v python3 >/dev/null 2>&1 || { err "python3 missing"; exit 1; }
    ok "python3 → $(python3 --version 2>&1)"
    if ! python3 -m pip --version >/dev/null 2>&1; then
        python3 -m ensurepip --upgrade >/dev/null 2>&1 || true
    fi
    python3 -m pip --version >/dev/null 2>&1 || { err "pip missing"; exit 1; }
    ok "pip → $(python3 -m pip --version 2>&1 | head -n1)"

    step "Retiring eventlet (retired upstream)"
    if python3 -c "import eventlet" 2>/dev/null; then
        python3 -m pip uninstall -y --quiet eventlet 2>/dev/null \
            || python3 -m pip uninstall -y --quiet --break-system-packages eventlet 2>/dev/null \
            || warn "could not uninstall eventlet, manual cleanup may be needed"
        if python3 -c "import eventlet" 2>/dev/null; then
            err "eventlet still importable — remove it manually before launching"
            exit 1
        else
            ok "eventlet removed"
        fi
    else
        ok "eventlet not present"
    fi

    step "Installing Python packages (flask, flask-socketio, cryptography>=48, fips203)"
    pip_install_one() {
        local pkg="$1"
        python3 -m pip install --quiet --upgrade "$pkg" 2>/dev/null \
            || python3 -m pip install --quiet --upgrade --break-system-packages "$pkg" 2>/dev/null \
            || python3 -m pip install --quiet --upgrade --break-system-packages --force-reinstall "$pkg" 2>/dev/null
    }
    for pkg in "flask" "flask-socketio" "cryptography>=48" "fips203"; do
        if pip_install_one "$pkg"; then
            ok "$pkg"
        else
            err "$pkg — installation failed"
        fi
    done

    step "Organizing templates"
    mkdir -p templates
    local moved=0
    shopt -s nullglob
    for f in *.html; do
        if [ ! -e "templates/$f" ]; then
            mv -- "$f" "templates/$f" && { ok "moved $f → templates/$f"; moved=$((moved + 1)); }
        fi
    done
    shopt -u nullglob 2>/dev/null || true
    [ "$moved" -eq 0 ] && ok "templates/ already organized"

    step "Verifying runtime imports"
    if python3 - <<'PY'
import sys
missing = []
for m in ("flask", "flask_socketio", "cryptography"):
    try: __import__(m)
    except ImportError: missing.append(m)
if missing:
    print("missing:", ", ".join(missing)); sys.exit(1)
from cryptography.hazmat.primitives.asymmetric import mldsa  # noqa: F401
import fips203  # noqa: F401
try:
    __import__("eventlet"); print("eventlet still installed"); sys.exit(1)
except ImportError: pass
PY
    then ok "All runtime imports resolve"
    else err "Verification failed — cryptography>=48 + libfips203.so required"; exit 1
    fi

    echo
    info "Generating offline E2EE key..."
    generate_key_internal

    echo
    banner "Debian install complete"
    printf "  ${C_DIM}Returning to Termux; the wizard will launch DDBox there.${RST}\n"
    echo
}

# ─────────────────────────────────────────────────────────────
#  Debian stage -key : standalone offline key regeneration
#  (port of gayken.sh)
# ─────────────────────────────────────────────────────────────
generate_key_internal() {
    command -v python3 >/dev/null 2>&1 || { err "python3 missing"; return 1; }
    local key
    key=$(python3 -c 'import secrets; print(secrets.token_hex(32))')
    if [ "${#key}" -ne 64 ]; then
        err "generated key is not 64 hex characters"
        return 1
    fi
    printf "  ${C_GREEN}[+] 256-bit (64-hex) key:${RST}\n\n"
    printf "    ${C_WHITE}${key}${RST}\n\n"
    printf "  ${C_DIM}Paste this into the DDBox web UI's Offline E2EE key prompt.${RST}\n"
    printf "  ${C_DIM}Share with recipients out-of-band only.${RST}\n"
}

run_debian_key() {
    TOTAL_STEPS=1; CURRENT_STEP=0
    echo
    banner "DDBox  ──  offline E2EE key generator"
    printf "  ${C_DIM}Author: D373Y 5373M   Version 1.2.0${RST}\n"
    step "Generating 256-bit key"
    generate_key_internal
}

# ─────────────────────────────────────────────────────────────
#  Debian stage -launch : start the app
# ─────────────────────────────────────────────────────────────
run_debian_launch() {
    cd /root/ddbox 2>/dev/null || { err "/root/ddbox not found"; exit 1; }
    [ -x ./ngrok ] || { err "ngrok not found in $(pwd) — run install.sh -2 first"; exit 1; }
    [ -f main.py ] || { err "main.py not found in $(pwd)"; exit 1; }
    echo
    banner "DDBox  ──  launching"
    printf "  ${C_DIM}Ctrl-C to stop. Keep this Termux session open.${RST}\n\n"
    exec bash -c 'python3 main.py | ./ngrok http 5000'
}

# ─────────────────────────────────────────────────────────────
#  Termux side — every Debian action goes through proot-distro
# ─────────────────────────────────────────────────────────────
run_termux() {
    TOTAL_STEPS=6; CURRENT_STEP=0
    echo
    banner "DDBox  ──  autoinstallation wizard (Termux)"
    printf "  ${C_DIM}Author: D373Y 5373M   Version 1.2.0${RST}\n"

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

    step "Installing DDBox inside Debian (deps + setup + key)"
    echo
    info "Running: proot-distro login debian -- bash -c \"... install.sh -2\""
    echo
    # Clone + run stage -2 inside Debian; -2 chains to -3; both run inside
    # the same proot-distro session. Nothing runs in Termux.
    if ! proot-distro login debian -- bash -c \
        "cd /root && rm -rf ddbox && apt update && apt install -y git && git clone https://github.com/DeleySelem/ddbox && cd ddbox && bash install.sh -2"; then
        err "Debian-side install failed"
        exit 1
    fi

    step "Creating 'ddbox' launcher"
    local DD="${PREFIX:-/data/data/com.termux/files/usr}/bin/ddbox"
    cat > "$DD" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# ddbox — launch DDBox inside proot-distro Debian.
# Never runs the program in Termux; uses `install.sh -launch` inside Debian.
set -e
exec proot-distro login debian -- bash -c 'cd /root/ddbox && bash install.sh -launch'
EOF
    chmod +x "$DD"
    ok "Launcher installed: $DD"

    step "Verifying launcher"
    if [ -x "$DD" ]; then
        ok "ddbox command ready"
    else
        err "launcher missing"; exit 1
    fi

    echo
    banner "DDBox installation complete"
    printf "  ${C_LGRAY}Launch from anywhere:${RST}  ${C_WHITE}ddbox${RST}\n"
    echo
    info "Logging into Debian and starting DDBox..."
    sleep 1

    # Final action: actually login to Debian and launch the app there.
    # Never invokes python3 / ngrok in Termux.
    exec proot-distro login debian -- bash -c 'cd /root/ddbox && bash install.sh -launch'
}

# ─────────────────────────────────────────────────────────────
#  Dispatch
# ─────────────────────────────────────────────────────────────
ARG="${1:-}"

if is_termux_host; then
    if [ -z "$ARG" ]; then
        run_termux
    else
        err "install.sh $ARG must be run INSIDE Debian, not in Termux."
        err "From Termux, run install.sh with no arguments."
        exit 1
    fi
else
    case "$ARG" in
        -2)      run_debian_deps ;;
        -3)      run_debian_setup ;;
        -key)    run_debian_key ;;
        -launch) run_debian_launch ;;
        "")
            err "install.sh (no arg) is Termux-only."
            err "Inside Debian use: install.sh -2 | -3 | -key | -launch"
            exit 1
            ;;
        *)
            err "Unknown option: $ARG"
            err "Valid: -2 | -3 | -key | -launch (inside Debian)"
            exit 1
            ;;
    esac
fi