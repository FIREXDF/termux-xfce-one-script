#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "==== Termux XFCE Installer ===="

if [ ! -d "/data/data/com.termux/files/usr" ]; then
echo "This script must run inside Termux."
exit 1
fi

ANDROID_API=$(getprop ro.build.version.sdk)
ARCH=$(dpkg --print-architecture)

echo "Android API: $ANDROID_API"
echo "Architecture: $ARCH"

if [ "$ANDROID_API" -lt 26 ]; then
echo "Android 8+ required for Termux:X11"
exit 1
fi

echo "Updating packages..."
pkg update -y
pkg upgrade -y

echo "Installing dependencies..."
pkg install -y proot-distro x11-repo termux-x11-nightly git curl wget nano

echo ""
echo "Enable GPU acceleration?"
echo "1) Yes"
echo "2) No"
read -p "Choose [1-2] (default 2): " GPU_CHOICE

GPU="false"

if [ "$GPU_CHOICE" = "1" ]; then
GPU="true"
pkg install -y virglrenderer-android
fi

echo ""
echo "Available distributions:"
proot-distro list

echo ""
read -p "Choose distribution (default: debian): " DISTRO

DISTRO=$(echo "${DISTRO:-debian}" | tr -d "[:space:]")

if ! proot-distro list | grep -qx "$DISTRO"; then
echo "Invalid distribution."
exit 1
fi

if proot-distro list-installed | awk '{print $1}' | grep -qx "$DISTRO"; then
echo "$DISTRO already installed."
else
echo "Installing $DISTRO..."
proot-distro install "$DISTRO"
fi

echo "Installing XFCE..."

proot-distro login "$DISTRO" --shared-tmp -- bash -c '

if command -v apt >/dev/null 2>&1; then
apt update
apt install -y xfce4 xfce4-goodies dbus-x11 sudo
elif command -v pacman >/dev/null 2>&1; then
pacman -Syu --noconfirm
pacman -S --noconfirm xfce4 xfce4-goodies sudo
elif command -v apk >/dev/null 2>&1; then
apk update
apk add xfce4 xfce4-terminal sudo
fi

'

echo "Creating startxfce..."

cat > ~/startxfce <<EOF
#!/data/data/com.termux/files/usr/bin/bash

GPU="$GPU"
DISTRO="$DISTRO"

pkill -f termux.x11 2>/dev/null
pkill -f virgl_test_server_android 2>/dev/null

termux-x11 :0 &
sleep 2

export DISPLAY=:0
export XDG_RUNTIME_DIR=\$TMPDIR

if [ "\$GPU" = "true" ]; then
virgl_test_server_android &
sleep 1
fi

proot-distro login \$DISTRO --shared-tmp -- bash -c "
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp
if [ '\$GPU' = 'true' ]; then
export GALLIUM_DRIVER=virpipe
fi
dbus-launch --exit-with-session startxfce4
"
EOF

chmod +x ~/startxfce

echo "Creating stopxfce..."

cat > ~/stopxfce <<EOF
#!/data/data/com.termux/files/usr/bin/bash
pkill -f startxfce4
pkill -f xfce4-session
pkill -f termux.x11
pkill -f virgl_test_server_android
EOF

chmod +x ~/stopxfce

echo 'alias startxfce="$HOME/startxfce"' >> ~/.bashrc
echo 'alias stopxfce="$HOME/stopxfce"' >> ~/.bashrc

echo ""
echo "Installation finished!"
echo ""
echo "Open the Termux:X11 app first."
echo ""
echo "Start XFCE:"
echo "startxfce"
echo ""
echo "Stop XFCE:"
echo "stopxfce"