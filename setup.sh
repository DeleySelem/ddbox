#!/usr/bin/env bash
# =============================================================
#   DDBox - setup
#   Installs build/PQ prerequisites, upgrades PQ Python deps,
#   organizes templates, and verifies runtime imports
# =============================================================
set -uo pipefail

RST=$'\033[0m'
B=$'\033[1m'
C_RED=$'\033[1;38;2;255;60;60m'
C_LGRAY=$'\033[38;2;190;190;190m'
C_BLUE=$'\033[1;38;2;80;140;255m'
C_WHITE=$'\033[1;38;2;255;255;255m'
C_DIM=$'\033[2;38;2;150;150;150m'

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

APT_UPDATED=0
install_sys_pkg() {
    local mgr
    mgr=$(detect_pkg_mgr)
    if [ -z "$mgr" ]; then err "no supported package manager"; return 1; fi
    case "$mgr" in
        apt-get)
            if [ "$APT_UPDATED" -eq 0 ]; then
                with_sudo apt-get update -qq || warn "apt update failed"
                APT_UPDATED=1
            fi
            with_sudo apt-get install -y "$@"
            ;;
        dnf|yum) with_sudo "$mgr" install -y "$@" ;;
        pacman) with_sudo pacman -S --noconfirm --needed "$@" ;;
        zypper) with_sudo zypper --non-interactive install "$@" ;;
        brew)   brew install "$@" ;;
    esac
}

ensure_sys_tools() {
    local mgr missing_pkgs=()
    mgr=$(detect_pkg_mgr)
    [ -z "$mgr" ] && return 0

    if [ "$mgr" = "apt-get" ]; then
        have gcc     || missing_pkgs+=(build-essential)
        have cargo   || missing_pkgs+=(cargo)
        have rustc   || missing_pkgs+=(rustc)
        dpkg -s libssl-dev >/dev/null 2>&1 || missing_pkgs+=(libssl-dev)
        dpkg -s libffi-dev >/dev/null 2>&1 || missing_pkgs+=(libffi-dev)
        if [ "${#missing_pkgs[@]}" -gt 0 ]; then
            info "installing system build/Rust deps: ${missing_pkgs[*]}"
            install_sys_pkg "${missing_pkgs[@]}" || warn "some system packages failed to install"
        else
            ok "system build & Rust toolchain present"
        fi
    fi
}

pip_install_pkg() {
    local pkg="$1" extra_flags="${2:-}"
    # shellcheck disable=SC2086
    python3 -m pip install $extra_flags --quiet "$pkg" 2>/dev/null \
        || python3 -m pip install $extra_flags --quiet --user "$pkg" 2>/dev/null \
        || python3 -m pip install $extra_flags --quiet --break-system-packages "$pkg" 2>/dev/null
}

ensure_py_pkg() {
    local pkg="$1" mod="$2" check_code="${3:-import $mod}"
    if python3 -c "$check_code" 2>/dev/null; then
        info "$pkg present — checking/upgrading"
        pip_install_pkg "$pkg" "--upgrade" || warn "$pkg could not be upgraded — continuing"
        ok "$pkg"
    else
        info "installing/upgrading $pkg"
        if ! pip_install_pkg "$pkg" "--upgrade"; then
            pip_install_pkg "$pkg" "--upgrade --force-reinstall" || {
                err "failed to install $pkg"
                return 1
            }
        fi
        if ! python3 -c "$check_code" 2>/dev/null; then
            info "retrying $pkg with --force-reinstall to override older system package"
            pip_install_pkg "$pkg" "--upgrade --force-reinstall" || true
        fi
        ok "$pkg"
    fi
}

# =============================================================
#                          START
# =============================================================
clear
echo
heat "         D D B o x --- s e t u p"
echo
echo "Author: D373Y 5373M"
echo "Version: v1.0.4"
printf "  ${C_DIM}post-quantum dead-drop chat environment bootstrap${RST}\n"

# -------------------- 1. Python & Build Prerequisites --------------------
title "1.  Python & system prerequisites" "$C_BLUE"
if have python3; then
    ok "python3 → $(python3 --version 2>&1)"
else
    warn "python3 not found installing"
    install_sys_pkg python3 || { err "python3 install failed"; exit 1; }
    ok "python3 → $(python3 --version 2>&1)"
fi

if python3 -m pip --version >/dev/null 2>&1; then
    ok "pip → $(python3 -m pip --version 2>&1 | head -n1)"
else
    warn "pip not found installing"
    install_sys_pkg python3-pip || install_sys_pkg python-pip || true
    python3 -m ensurepip --upgrade >/dev/null 2>&1 || true
    if python3 -m pip --version >/dev/null 2>&1; then
        ok "pip → $(python3 -m pip --version 2>&1 | head -n1)"
    else
        err "pip still missing"; exit 1
    fi
fi

ensure_sys_tools

# -------------------- 2. Remove Eventlet (retired upstream) --------------------
title "2.  Retire Eventlet" "$C_RED"
if python3 -c "import eventlet" 2>/dev/null; then
    warn "eventlet detected uninstalling stream retirement)"
    python3 -m pip uninstall -y --quiet eventlet 2>/dev/null \
        || python3 -m pip uninstall -y --quiet --break-system-packages eventlet 2>/dev/null \
        || warn "could not uninstall eventlet manual cleanup may be needed"
    if python3 -c "import eventlet" 2>/dev/null; then
        err "eventlet still importable remove it manually before running DDBox"
    else
        ok "eventlet removed"
    fi
else
    ok "eventlet not present"
fi

# -------------------- 3. Python Packages (Flask, SocketIO, ML-DSA-87, ML-KEM-1024) --------------------
title "3.  Python packages" "$C_WHITE"
ensure_py_pkg "flask"            "flask"          "import flask" || true
ensure_py_pkg "flask-socketio"   "flask_socketio" "import flask_socketio" || true
ensure_py_pkg "cryptography>=48" "cryptography"   "from cryptography.hazmat.primitives.asymmetric import mldsa" || true
ensure_py_pkg "fips203"          "fips203"        "import fips203" || true

# -------------------- 4. Project Layout --------------------
title "4.  Project layout" "$C_BLUE"
if [ -d templates ]; then
    ok "templates/ already exists"
else
    mkdir -p templates && ok "created templates/"
fi

moved=0
shopt -s nullglob
for f in *.html; do
    if [ -e "templates/$f" ]; then
        warn "$f already exists in templates/ leaving root copy"
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

# -------------------- 5. Verification --------------------
title "5.  Verification" "$C_BLUE"
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

import cryptography
try:
    from cryptography.hazmat.primitives.asymmetric import mldsa  # noqa: F401
except ImportError as exc:
    print(f"cryptography ({cryptography.__version__} at {cryptography.__file__}) missing mldsa:", exc)
    sys.exit(1)

try:
    import fips203  # noqa: F401
except OSError as exc:
    print("fips203 native library missing (libfips203.so):", exc)
    sys.exit(1)
except ImportError:
    print("missing: fips203")
    sys.exit(1)

try:
    __import__("eventlet")
    print("eventlet is still installed remove it")
    sys.exit(1)
except ImportError:
    pass
PY
then
    ok "all imports resolve (flask, flask_socketio, cryptography mldsa, fips203), eventlet absent"
else
    err "verification failed ensure cryptography>=48 and libfips203.so are installed or FIPS203_PYTHON_TESTING_LIBRARY is set"
    exit 1
fi

echo
hr
echo
heat "         s e t u p   c o m p l e t e"
echo[B
printf "  ${C_LGRAY}start with:${RST}  ${C_WHITE}python3 main.py${RST}\n"
printf "  ${C_LGRAY}then open:${RST}  ${C_BLUE}http://127.0.0.1:5000${RST}\n"
printf "  ${C_DIM}async backend: threading (eventlet retired) | PQ: ML-KEM-1024 + ML-DSA-87${RST}\n"
echo