#!/data/data/com.termux/files/usr/bin/bash
set -e

APP_NAME="X11 XFCE Setup"
START_SCRIPT="$HOME/startxfce"
STOP_SCRIPT="$HOME/stopxfce"
BASHRC="$HOME/.bashrc"

say(){ printf "%s\n" "$*"; }
die(){ say "Error: $*"; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

android_api() { getprop ro.build.version.sdk 2>/dev/null || echo ""; }
android_rel() { getprop ro.build.version.release 2>/dev/null || echo ""; }
arch_termux() { dpkg --print-architecture 2>/dev/null || uname -m; }

preflight() {
  [ -d /data/data/com.termux/files/usr ] || die "This must be run inside Termux."
  have pkg || die "Termux package manager (pkg) not found."
  have dpkg || die "dpkg not found (Termux is incomplete)."

  local api rel arch
  api="$(android_api)"
  rel="$(android_rel)"
  arch="$(arch_termux)"

  say "Device checks:"
  say "  Android: ${rel:-unknown} (SDK ${api:-unknown})"
  say "  Arch:    ${arch}"

  if [ -n "$api" ] && [ "$api" -lt 26 ]; then
    die "Android SDK < 26 detected. Termux:X11 generally requires Android 8+ (SDK 26+)."
  fi

  case "$arch" in
    aarch64|arm64|arm64-v8a|amd64|x86_64|i686|x86) ;;
    *)
      say "Warning: Unrecognized architecture '$arch'. Some packages may not exist."
      ;;
  esac

  if [ -n "${TERMUX_VERSION:-}" ]; then
    : # ok
  fi

  if have termux-setup-storage; then
    : # optional
  fi
}

ensure_pkg_updated() {
  say "Updating Termux..."
  pkg update -y
  pkg upgrade -y
}

ensure_termux_deps() {
  say "Installing Termux dependencies..."
  pkg install -y proot-distro git curl nano wget
  pkg install -y x11-repo
  pkg install -y termux-x11-nightly
}

choose_gpu() {
  say ""
  say "GPU acceleration (VirGL):"
  say "1) Enable"
  say "2) Disable"
  read -r -p "Choose [1-2] (default 2): " g
  case "${g:-2}" in
    1) echo "true" ;;
    *) echo "false" ;;
  esac
}

gpu_compat_check() {
  local gpu="$1"
  local arch
  arch="$(arch_termux)"

  if [ "$gpu" != "true" ]; then
    return 0
  fi

  case "$arch" in
    aarch64|arm64|arm64-v8a|amd64|x86_64)
      ;;
    *)
      say "Warning: GPU enabled but architecture '$arch' may not have virglrenderer-android packages."
      ;;
  esac
}

install_gpu_termux() {
  local gpu="$1"
  if [ "$gpu" = "true" ]; then
    say "Installing VirGL (Termux)..."
    pkg install -y virglrenderer-android || {
      say "Warning: Could not install virglrenderer-android. GPU mode will still be available but may not work."
    }
  else
    say "GPU disabled."
  fi
}

list_distros() {
  proot-distro list 2>/dev/null | sed '/^\s*$/d' || true
}

choose_distro() {
  say ""
  say "Available distributions (from proot-distro):"
  list_distros | sed 's/^/  - /'
  say ""
  read -r -p "Type distro name (example: debian, ubuntu, archlinux) [default: debian]: " d
  echo "${d:-debian}"
}

is_distro_installed() {
  local d="$1"
  proot-distro list-installed 2>/dev/null | awk '{print $1}' | grep -qx "$d"
}

ensure_distro_installed() {
  local d="$1"
  if is_distro_installed "$d"; then
    say "$d is already installed."
  else
    say "Installing $d..."
    proot-distro install "$d"
  fi
}

install_xfce_inside_distro() {
  local d="$1"
  say "Installing XFCE inside $d..."
  proot-distro login "$d" --shared-tmp -- bash -lc '
set -e
if command -v apt >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt install -y xfce4 xfce4-goodies dbus-x11 x11-xserver-utils sudo ca-certificates curl wget nano
elif command -v pacman >/dev/null 2>&1; then
  pacman -Syu --noconfirm
  pacman -S --noconfirm xfce4 xfce4-goodies dbus xorg-xsetroot sudo ca-certificates curl wget nano
elif command -v apk >/dev/null 2>&1; then
  apk update
  apk add xfce4 xfce4-terminal dbus-x11 xsetroot sudo ca-certificates curl wget nano
else
  echo "No supported package manager found (apt/pacman/apk)."
  exit 1
fi
'
}

write_start_script() {
  local d="$1"
  local gpu_default="$2"

  cat > "$START_SCRIPT" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
set -e

DISTRO="${d}"
GPU_DEFAULT="${gpu_default}"
GPU="\${1:-\$GPU_DEFAULT}"

if ! command -v termux-x11 >/dev/null 2>&1; then
  echo "termux-x11 not found. Install termux-x11-nightly in Termux."
  exit 1
fi

pkill -f "termux.x11" >/dev/null 2>&1 || true
pkill -f "virgl_test_server_android" >/dev/null 2>&1 || true

termux-x11 :0 >/dev/null 2>&1 &
sleep 1

export DISPLAY=:0
export XDG_RUNTIME_DIR="\$TMPDIR"

if [ "\$GPU" = "true" ]; then
  if command -v virgl_test_server_android >/dev/null 2>&1; then
    virgl_test_server_android >/dev/null 2>&1 &
    sleep 1
  else
    echo "VirGL server not found (virgl_test_server_android). GPU mode may not work."
  fi
fi

proot-distro login "\$DISTRO" --shared-tmp -- bash -lc "
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp
if [ '\$GPU' = 'true' ]; then
  export GALLIUM_DRIVER=virpipe
fi
dbus-launch --exit-with-session startxfce4
"
EOF

  chmod +x "$START_SCRIPT"
}

write_stop_script() {
  cat > "$STOP_SCRIPT" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
pkill -f "startxfce4" >/dev/null 2>&1 || true
pkill -f "xfce4-session" >/dev/null 2>&1 || true
pkill -f "termux.x11" >/dev/null 2>&1 || true
pkill -f "virgl_test_server_android" >/dev/null 2>&1 || true
EOF

  chmod +x "$STOP_SCRIPT"
}

ensure_aliases() {
  grep -q 'alias startxfce=' "$BASHRC" 2>/dev/null || echo 'alias startxfce="$HOME/startxfce"' >> "$BASHRC"
  grep -q 'alias stopxfce=' "$BASHRC" 2>/dev/null || echo 'alias stopxfce="$HOME/stopxfce"' >> "$BASHRC"
}

post_info() {
  local d="$1"
  local gpu="$2"
  say ""
  say "Done."
  say ""
  say "Before starting:"
  say "1) Install the Termux:X11 Android app."
  say "2) Open Termux:X11 once (keep it in background)."
  say ""
  say "Start:"
  say "  startxfce"
  say ""
  say "Override GPU:"
  say "  startxfce true"
  say "  startxfce false"
  say ""
  say "Stop:"
  say "  stopxfce"
  say ""
  say "Defaults:"
  say "  DISTRO=$d"
  say "  GPU_DEFAULT=$gpu"
}

say "==============================="
say "$APP_NAME"
say "==============================="

preflight
ensure_pkg_updated
ensure_termux_deps

GPU_DEFAULT="$(choose_gpu)"
gpu_compat_check "$GPU_DEFAULT"
install_gpu_termux "$GPU_DEFAULT"

DISTRO="$(choose_distro)"
ensure_distro_installed "$DISTRO"

install_xfce_inside_distro "$DISTRO"

write_start_script "$DISTRO" "$GPU_DEFAULT"
write_stop_script
ensure_aliases

. "$BASHRC" >/dev/null 2>&1 || true

post_info "$DISTRO" "$GPU_DEFAULT"