#!/usr/bin/env bash
# install.sh — DDBox unified installer
#   Termux mode   : bootstraps proot-distro Debian + installs `ddbox` launcher
#   Debian mode   : installs build tools, ngrok, DDBox deps, verifies runtime
#
# Author: D373Y 5373M  |  Version 1.0.10
set -uo pipefail

# ─────────────────────────────────────────────────────────────
#  Environment detection
# ─────────────────────────────────────────────────────────────
if command -v pkg >/dev/null 2>&1 && [ -d /data/data/com.termux ]; then
    MODE="termux"
else
    MODE="debian"
fi

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

# ─────────────────────────────────────────────────────────────
#  Rainbow progress bar (anchored to bottom line)
# ─────────────────────────────────────────────────────────────
TOTAL_STEPS=1
CURRENT_STEP=0
BAR_ACTIVE=0
TERM_LINES=24
TERM_COLS=80
RAINBOW_COLORS=()
RAINBOW_N=40

init_rainbow() {
    RAINBOW_COLORS=()
    local i hue rgb
    for ((i=0; i<RAINBOW_N; i++)); do
        hue=$(( i * 360 / RAINBOW_N ))
        rgb=$(awk -v h="$hue" 'BEGIN{
            h=h/60; s=1; v=1; c=v*s;
            hpm=h-int(h/2)*2; d=hpm-1; if(d<0)d=-d; x=c*(1-d);
            if(h<1){r=c;g=x;b=0} else if(h<2){r=x;g=c;b=0}
            else if(h<3){r=0;g=c;b=x} else if(h<4){r=0;g=x;b=c}
            else if(h<5){r=x;g=0;b=c} else{r=c;g=0;b=x}
            m=v-c;
            printf "%d;%d;%d", int((r+m)*255), int((g+m)*255), int((b+m)*255)
        }')
        RAINBOW_COLORS+=("$rgb")
    done
}

_term_size() {
    TERM_LINES=$(tput lines 2>/dev/null || echo 24)
    TERM_COLS=$(tput cols 2>/dev/null || echo 80)
    [ -z "$TERM_LINES" ] && TERM_LINES=24
    [ -z "$TERM_COLS" ]  && TERM_COLS=80
}

progress_bar() {
    local pct="${1:-0}" msg="${2:-}"

    if [ "$BAR_ACTIVE" -eq 0 ]; then
        printf '  [%3d%%] %s\n' "$pct" "$msg"
        return
    fi

    tput sc 2>/dev/null || true
    tput cup $((TERM_LINES - 1)) 0 2>/dev/null || true
    tput el 2>/dev/null || true

    local w=$(( TERM_COLS - 22 ))
    [ "$w" -lt 10 ] && w=10

    # NB: don't chain dependent assignments in one `local` — under `set -u`
    # bash expands all RHS expressions before assigning any of the names,
    # so `empty=$((w - filled))` would see `filled` as unbound.
    local filled empty
    filled=$(( w * pct / 100 ))
    empty=$(( w - filled ))

    local i idx
    for ((i=0; i<filled; i++)); do
        idx=$(( i * RAINBOW_N / w ))
        printf '\033[38;2;%sm█' "${RAINBOW_COLORS[$idx]}"
    done
    printf '%s' "$RST"
    for ((i=0; i<empty; i++)); do printf '░'; done
    printf ' %3d%% %s' "$pct" "$msg"
    tput rc 2>/dev/null || true
}

setup_bar() {
    if ! command -v tput >/dev/null 2>&1 || [ ! -t 1 ]; then
        BAR_ACTIVE=0; return
    fi
    _term_size
    [ "$TERM_LINES" -lt 6 ] && { BAR_ACTIVE=0; return; }
    BAR_ACTIVE=1
    init_rainbow
    tput csr 1 $((TERM_LINES - 1)) 2>/dev/null || true
    tput cup 0 0 2>/dev/null || true
    progress_bar 0 "starting..."
}

teardown_bar() {
    [ "$BAR_ACTIVE" -eq 0 ] && return
    tput csr 1 "$TERM_LINES" 2>/dev/null || true
    tput cup $((TERM_LINES - 1)) 0 2>/dev/null || true
    tput el 2>/dev/null || true
    printf '\n'
    BAR_ACTIVE=0
}

step() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local pct=$(( CURRENT_STEP * 100 / TOTAL_STEPS ))
    [ "$pct" -gt 100 ] && pct=100
    progress_bar "$pct" "$1"
    step_title "$1"
}

# ─────────────────────────────────────────────────────────────
#  Termux side
# ─────────────────────────────────────────────────────────────
run_termux() {
    TOTAL_STEPS=6; CURRENT_STEP=0
    trap 'teardown_bar' INT TERM
    printf '\n\n'
    setup_bar
    echo
    banner "DDBox  ──  autoinstallation wizard"
    printf "  ${C_DIM}Author: D373Y 5373M   Version 1.0.10${RST}\n"
    echo

    step "Updating Termux packages"
    pkg update -y && pkg upgrade -y || warn "pkg update/upgrade reported issues"

    step "Installing proot-distro"
    pkg install -y proot-distro || { err "proot-distro install failed"; teardown_bar; exit 1; }

    step "Checking Debian rootfs"
    # Login probe — the most reliable "is Debian usable?" test.
    if proot-distro login debian -- true >/dev/null 2>&1; then
        ok "Debian already installed — skipping, proceeding to login"
    else
        info "Installing Debian rootfs (this can take a while)..."
        # Termux has no writable /tmp — use $TMPDIR (=$PREFIX/tmp) with fallback
        DDLOG="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}/ddbox-pd-install.log"
        mkdir -p "$(dirname "$DDLOG")" 2>/dev/null || true
        proot-distro install debian 2>&1 | tee "$DDLOG"
        rc=${PIPESTATUS[0]}
        if [ "$rc" -ne 0 ]; then
            if grep -qi 'already exists' "$DDLOG" 2>/dev/null; then
                ok "Debian already exists — proceeding to login"
            else
                err "Debian install failed"
                teardown_bar
                exit 1
            fi
        else
            ok "Debian installed"
        fi
    fi

    step "Installing DDBox inside Debian"
    teardown_bar
    echo
    info "Entering Debian for the heavy install..."
    echo
    if ! proot-distro login debian -- bash -c '
        set -uo pipefail
        export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
        APT_OPTS=(-y -o "Dpkg::Options::=--force-confold" -o "Dpkg::Options::=--force-confdef")
        apt-get update "${APT_OPTS[@]}" || true
        apt-get install "${APT_OPTS[@]}" --no-install-recommends git ca-certificates curl || exit 1
        if [ -d /root/ddbox/.git ]; then
            cd /root/ddbox && git pull --ff-only 2>/dev/null || true
        else
            rm -rf /root/ddbox
            git clone https://github.com/DeleySelem/ddbox /root/ddbox || exit 1
        fi
        cd /root/ddbox
        exec bash install.sh
    '; then
        err "Debian-side install failed"
        exit 1
    fi

    printf '\n\n'
    setup_bar
    echo

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
    if [ -x "$DD" ]; then ok "ddbox command ready"; else err "launcher missing"; fi

    progress_bar 100 "complete"
    teardown_bar
    echo
    banner "DDBox installation complete"
    printf "  ${C_LGRAY}Launch from anywhere:${RST}  ${C_WHITE}ddbox${RST}\n"
    printf "  ${C_DIM}First launch starts python + ngrok inside Debian.${RST}\n"
    echo
}

# ─────────────────────────────────────────────────────────────
#  Debian side
# ─────────────────────────────────────────────────────────────
run_debian() {
    export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
    APT_OPTS=(-y -o "Dpkg::Options::=--force-confold" -o "Dpkg::Options::=--force-confdef")
    TOTAL_STEPS=7; CURRENT_STEP=0
    trap 'teardown_bar' INT TERM
    printf '\n\n'
    setup_bar
    echo
    banner "DDBox  ──  Debian install (2 of 2)"
    printf "  ${C_DIM}Author: D373Y 5373M   Version 1.0.10${RST}\n"
    echo

    step "Updating APT index"
    apt-get update "${APT_OPTS[@]}" || warn "apt-get update reported issues"

    step "Installing build tools, Rust, Python"
    apt-get install "${APT_OPTS[@]}" --no-install-recommends \
        git curl unzip wget ca-certificates \
        build-essential libssl-dev libffi-dev \
        rustc cargo python3-pip python3-venv \
        || { err "APT install failed"; teardown_bar; exit 1; }
    ok "System packages installed"

    step "Installing ngrok (from ddbox folder)"
    if [ ! -x ./ngrok ]; then
        curl -fsSL https://bin.ngrok.com/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz | tar -xz \
            || { err "ngrok download failed"; teardown_bar; exit 1; }
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
        read -r NGROK_TOKEN
        if [ -n "${NGROK_TOKEN:-}" ]; then
            ./ngrok authtoken "$NGROK_TOKEN" && ok "ngrok token saved" || warn "ngrok authtoken failed"
        else
            warn "No token entered — you can run: ./ngrok authtoken <TOKEN> later"
        fi
    fi

    step "Running setup.sh (pip: cryptography>=48, fips203)"
    if [ -f setup.sh ]; then
        bash setup.sh || { err "setup.sh failed"; teardown_bar; exit 1; }
    else
        err "setup.sh not found in $(pwd)"; teardown_bar; exit 1
    fi

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
    else warn "Verification reported issues"; fi

    step "Generating offline E2EE key"
    if [ -f gayken.sh ]; then
        bash gayken.sh || warn "gayken.sh reported issues"
    else
        warn "gayken.sh not found"
    fi

    progress_bar 100 "complete"
    teardown_bar
    echo
    banner "Debian-side install complete"
    printf "  ${C_DIM}Return to Termux and run:${RST}  ${C_WHITE}ddbox${RST}\n"
    echo
}

# ─────────────────────────────────────────────────────────────
#  Dispatch
# ─────────────────────────────────────────────────────────────
case "$MODE" in
    termux) run_termux ;;
    *)      run_debian ;;
esac