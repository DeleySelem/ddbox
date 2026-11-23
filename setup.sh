#!/usr/bin/env bash
# =============================================================
#   DDBox — setup.sh
#   Installs / updates dependencies, then organizes templates
# =============================================================
set -uo pipefail

# -------------------- ANSI palette --------------------
RST=$'\033[0m'
B=$'\033[1m'
C_RED=$'\033[1;38;2;255;60;60m'
C_LGRAY=$'\033[38;2;190;190;190m'
C_BLUE=$'\033[1;38;2;80;140;255m'
C_WHITE=$'\033[1;38;2;255;255;255m'
C_DIM=$'\033[2;38;2;150;150;150m'

# -------------------- Heat-map gradient --------------------
# Blends blue -> cyan -> yellow -> red per character.
heat() {
    awk -v text="$1" \
        -v stops="0;120;255 0;220;220 255;220;0 255;60;60" '
    BEGIN {
        n = split(stops, arr, " ");
        len = length(text);
        for (i = 0; i < len; i++) {
            ch  = substr(text, i+1, 1);
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

# -------------------- Logging --------------------
ok()   { printf "  ${C_WHITE}✓${RST}  ${C_LGRAY}%s${RST}\n" "$*"; }
info() { printf "  ${C_BLUE}→${RST}  ${C_LGRAY}%s${RST}\n" "$*"; }
warn() { printf "  ${C_RED}⚠${RST}  ${C_LGRAY}%s${RST}\n" "$*"; }
err()  { printf "  ${C_RED}✗${RST}  ${C_RED}%s${RST}\n" "$*"; }
hr()   { printf "  ${C_DIM}%s${RST}\n" "$(printf '─%.0s' $(seq 1 60))"; }
title() {
    local label="$1" color="${2:-$C_BLUE}"
    echo
    printf "  ${B}${color}▸ %s${RST}\n" "$label"
    hr
}

have() { command -v "$1" >/dev/null 2>&1; }

detect_pkg_mgr() {
    local m
    for m in apt-get dnf yum pacman zypper brew; do
        have "$m" && { echo "$m"; return; }
    done
}

with_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif have sudo; then
        sudo "$@"
    else
        err "requires root, sudo unavailable: $*"
        return 1
    fi
}

install_sys_pkg() {
    local mgr
    mgr=$(detect_pkg_mgr)
    if [ -z "$mgr" ]; then err "no supported package manager"; return 1; fi
    case "$mgr" in
        apt-get) with_sudo apt-get update -qq || warn "apt update failed"; with_sudo apt-get install -y "$@" ;;
        dnf|yum) with_sudo "$mgr" install -y "$@" ;;
        pacman) with_sudo pacman -S --noconfirm --needed "$@" ;;
        zypper) with_sudo zypper --non-interactive install "$@" ;;
        brew)   brew install "$@" ;;
    esac
}

ensure_py_pkg() {
    local pkg="$1" mod="$2"
    if python3 -c "import $mod" 2>/dev/null; then
        info "$pkg present — upgrading"
        python3 -m pip install --upgrade --quiet "$pkg" 2>/dev/null \
            || python3 -m pip install --upgrade --quiet --user "$pkg" 2>/dev/null \
            || python3 -m pip install --upgrade --quiet --break-system-packages "$pkg" 2>/dev/null \
            || warn "$pkg could not be upgraded (system-locked) — continuing"
        ok "$pkg"
    else
        info "installing $pkg"
        python3 -m pip install --quiet "$pkg" 2>/dev/null \
            || python3 -m pip install --quiet --user "$pkg" 2>/dev/null \
            || python3 -m pip install --quiet --break-system-packages "$pkg" 2>/dev/null \
            || { err "failed to install $pkg"; return 1; }
        ok "$pkg"
    fi
}

# =============================================================
#                          START
# =============================================================
clear
echo
heat "         D D B o x   ─   s e t u p"
echo
printf "  ${C_DIM}encrypted dead-drop chat — environment bootstrap${RST}\n"

# -------------------- 1. Python --------------------
title "1.  Python interpreter" "$C_BLUE"
if have python3; then
    ok "python3 → $(python3 --version 2>&1)"
else
    warn "python3 not found — installing"
    install_sys_pkg python3 || { err "python3 install failed"; exit 1; }
    ok "python3 → $(python3 --version 2>&1)"
fi

if python3 -m pip --version >/dev/null 2>&1; then
    ok "pip → $(python3 -m pip --version 2>&1 | head -n1)"
else
    warn "pip not found — installing"
    install_sys_pkg python3-pip || install_sys_pkg python-pip || true
    python3 -m ensurepip --upgrade >/dev/null 2>&1 || true
    if python3 -m pip --version >/dev/null 2>&1; then
        ok "pip → $(python3 -m pip --version 2>&1 | head -n1)"
    else
        err "pip still missing"; exit 1
    fi
fi

# -------------------- 2. Python packages --------------------
title "2.  Python packages" "$C_WHITE"
ensure_py_pkg "flask"          "flask"          || true
ensure_py_pkg "flask-socketio" "flask_socketio" || true
ensure_py_pkg "cryptography"   "cryptography"   || true

# -------------------- 3. Layout --------------------
title "3.  Project layout" "$C_RED"
if [ -d templates ]; then
    ok "templates/ already exists"
else
    mkdir -p templates && ok "created templates/"
fi

moved=0
shopt -s nullglob
for f in *.html; do
    if [ -e "templates/$f" ]; then
        warn "$f already exists in templates/ — leaving root copy"
    else
        if mv -- "$f" "templates/$f"; then
            ok "moved  $f  →  templates/$f"
            moved=$((moved + 1))
        fi
    fi
done
shopt -u nullglob 2>/dev/null || true

if [ "$moved" -eq 0 ]; then
    if [ -z "$(ls -A templates 2>/dev/null)" ]; then
        warn "no .html files found in project root"
    else
        info "no pending .html files (already organized)"
    fi
fi

# -------------------- 4. Verify --------------------
title "4.  Verification" "$C_BLUE"
if python3 - <<'PY'
import sys
missing = []
for m in ("flask", "flask_socketio", "cryptography"):
    try:
        __import__(m)
    except ImportError:
        missing.append(m)
if missing:
    print("missing:", ", ".join(missing))
    sys.exit(1)
PY
then
    ok "all imports resolve"
else
    err "some imports failed — re-run setup"
    exit 1
fi

# -------------------- Done --------------------
echo
hr
echo
heat "         s e t u p   c o m p l e t e"
echo
printf "  ${C_LGRAY}start with:${RST}  ${C_WHITE}python3 main.py${RST}\n"
printf "  ${C_LGRAY}then open:${RST}  ${C_BLUE}http://127.0.0.1:5000${RST}\n"
echo