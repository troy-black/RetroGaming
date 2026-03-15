#!/bin/bash
# ==============================================================================
# Script: arcade.sh
# Description: Automated deployment and autostart script for Ubuntu Cinnamon
#              retro gaming environment. Handles dependency installation,
#              RetroArch/ES-DE setup, secure Samba mounts, WebDAV configuration,
#              and conditional autostart logic.
#
# Deployment Execution:
#   Run the following commands in your terminal to download and execute:
#   wget https://raw.githubusercontent.com/troy-black/RetroGaming/refs/heads/main/arcade.sh -O ~/arcade.sh
#   chmod +x ~/arcade.sh
#   ~/arcade.sh
# ==============================================================================

# ------------------------------------------------------------------------------
# Phase 1: Autostart Logic (Executed via Cinnamon Startup Registry)
# ------------------------------------------------------------------------------
if [ "$1" = "--autostart" ]; then
    # Allow desktop environment and network mounts to initialize
    sleep 5

    # Check for character devices associated with joysticks/gamepads
    if ls /dev/input/js* 1> /dev/null 2>&1; then
        echo "Gamepad detected. Initializing EmulationStation Desktop Edition."
        flatpak run org.es_de.frontend
    else
        echo "No gamepad detected. Exiting script."
    fi

    # Exit gracefully so the rest of the installation script does not run
    exit 0
fi

# ------------------------------------------------------------------------------
# Phase 2: Initial Setup Logic (Executed by the User)
# ------------------------------------------------------------------------------
echo "Initializing system configuration..."

# Gather Configuration Details
echo "Please provide the following configuration details."
echo "Note: Passwords will not be displayed on screen."

read -p "Enter WebDAV URL (e.g., https://webdav/): " WEBDAV_URL
read -p "Enter WebDAV Username: " WEBDAV_USER
read -s -p "Enter WebDAV Password: " WEBDAV_PASS
echo ""

read -p "Enter Samba Host/Domain (e.g., server_host): " SMB_HOST
read -p "Enter Samba Username: " SMB_USER
read -s -p "Enter Samba Password: " SMB_PASS
echo ""

# System Update & Dependencies
echo "Updating package lists and installing required dependencies..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y cifs-utils joystick jstest-gtk steam-installer flatpak

# Flatpak & Application Installation
echo "Adding Flathub repository and installing emulation software..."
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
sudo flatpak install -y flathub org.libretro.RetroArch
sudo flatpak install -y flathub org.es_de.frontend

echo "Creating Samba mount point..."
sudo mkdir -p /mnt/shared
sudo chown "$USER":"$USER" /mnt/shared

# RetroArch WebDAV Configuration
echo "Applying RetroArch WebDAV configuration..."
RA_CONFIG_DIR="$HOME/.var/app/org.libretro.RetroArch/config/retroarch"
RA_CONFIG_FILE="$RA_CONFIG_DIR/retroarch.cfg"

mkdir -p "$RA_CONFIG_DIR"
if [ ! -f "$RA_CONFIG_FILE" ]; then
    touch "$RA_CONFIG_FILE"
fi

for KEY in network_webdav_url network_webdav_username network_webdav_password; do
    VAR_NAME=$(echo "$KEY" | sed 's/network_webdav_//' | tr '[:lower:]' '[:upper:]')
    if [ "$VAR_NAME" = "URL" ]; then VAL="$WEBDAV_URL"; fi
    if [ "$VAR_NAME" = "USERNAME" ]; then VAL="$WEBDAV_USER"; fi
    if [ "$VAR_NAME" = "PASSWORD" ]; then VAL="$WEBDAV_PASS"; fi

    if grep -q "^$KEY" "$RA_CONFIG_FILE"; then
        sed -i "s|^$KEY = .*|$KEY = \"$VAL\"|" "$RA_CONFIG_FILE"
    else
        echo "$KEY = \"$VAL\"" >> "$RA_CONFIG_FILE"
    fi
done

if grep -q "^network_webdav_enable" "$RA_CONFIG_FILE"; then
    sed -i 's|^network_webdav_enable = .*|network_webdav_enable = "true"|' "$RA_CONFIG_FILE"
else
    echo 'network_webdav_enable = "true"' >> "$RA_CONFIG_FILE"
fi

# Samba Mount Configuration
echo "Configuring Samba credentials and fstab entry..."

echo "username=$SMB_USER" > "$HOME/.smbcredentials"
echo "password=$SMB_PASS" >> "$HOME/.smbcredentials"
chmod 600 "$HOME/.smbcredentials"

if ! grep -q "//${SMB_HOST}/shared" /etc/fstab; then
    echo "//${SMB_HOST}/shared /mnt/shared cifs credentials=$HOME/.smbcredentials,uid=$(id -u),gid=$(id -g),x-systemd.automount,x-systemd.requires=network-online.target,iocharset=utf8 0 0" | sudo tee -a /etc/fstab
fi

# Configure Cinnamon Autostart Registry
echo "Registering script with Cinnamon Startup Applications..."
AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

# Generate a .desktop file to trigger the --autostart parameter on login
cat <<EOF > "$AUTOSTART_DIR/arcade_autostart.desktop"
[Desktop Entry]
Type=Application
Exec=$HOME/arcade.sh --autostart
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name=Arcade Autostart Logic
Comment=Checks for a connected gamepad and launches EmulationStation-DE
EOF

echo "Configuration complete. Please restart the system to finalize the setup."