#!/data/data/com.termux/files/usr/bin/bash

# GPU mode: true or false
GPU="${1:-false}"
DISTRO="debian"

echo "Updating Termux packages..."
pkg update -y
pkg upgrade -y

echo "Installing required repositories..."
pkg install -y x11-repo

echo "Installing base packages..."
pkg install -y proot-distro termux-x11-nightly git curl nano wget

if [ "$GPU" = "true" ]; then
    echo "Installing VirGL GPU support..."
    pkg install -y virglrenderer-android
fi

echo "Installing Linux distribution..."
if ! proot-distro list-installed | grep -q "$DISTRO"; then
    proot-distro install "$DISTRO"
fi

echo "Installing XFCE inside Linux..."
proot-distro login "$DISTRO" --shared-tmp -- bash -c "
apt update
apt install -y xfce4 xfce4-goodies dbus-x11 x11-xserver-utils sudo nano wget curl
"

echo "Creating XFCE start script..."

cat > ~/startxfce << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

GPU="${1:-false}"

pkill -f termux.x11 2>/dev/null
pkill -f virgl_test_server_android 2>/dev/null

termux-x11 :0 &
sleep 2

export DISPLAY=:0
export XDG_RUNTIME_DIR=$TMPDIR

if [ "$GPU" = "true" ]; then
    virgl_test_server_android &
    sleep 1
fi

proot-distro login debian --shared-tmp -- bash -c "
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp
if [ \"$GPU\" = \"true\" ]; then
export GALLIUM_DRIVER=virpipe
fi
dbus-launch --exit-with-session startxfce4
"
EOF

chmod +x ~/startxfce

echo "Creating stop script..."

cat > ~/stopxfce << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
pkill -f startxfce4
pkill -f xfce4-session
pkill -f termux.x11
pkill -f virgl_test_server_android
EOF

chmod +x ~/stopxfce

echo "Adding shortcuts..."
echo 'alias startxfce="$HOME/startxfce"' >> ~/.bashrc
echo 'alias stopxfce="$HOME/stopxfce"' >> ~/.bashrc

echo ""
echo "Installation complete."
echo ""
echo "Open the Termux:X11 application first."
echo ""
echo "Start XFCE:"
echo "startxfce false"
echo ""
echo "Start XFCE with GPU:"
echo "startxfce true"
