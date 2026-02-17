#!/bin/sh
set -e

REPO="alessandrodn/mountbox"
VERSION="${VERSION:?Usage: VERSION=x.y.z sh setup.sh}"
FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
    esac
done

# --- Version check ---
VERSION_FILE="/etc/mountbox/VERSION"
if [ "$FORCE" -eq 0 ] && [ -f "$VERSION_FILE" ] && [ "$(cat "$VERSION_FILE")" = "$VERSION" ]; then
    logger -t mountbox "Setup skipped: v${VERSION} is already installed (use --force to reinstall)"
    echo "MountBox v${VERSION} is already installed. Use --force to reinstall."
    exit 0
fi

echo "=== MountBox v${VERSION} Setup ==="
echo "Configuring Alpine Linux as a USB mount server..."
echo ""

# --- Download repo tarball ---
echo "Downloading MountBox v${VERSION}..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
wget -qO- "https://github.com/$REPO/archive/v${VERSION}.tar.gz" | tar xz -C "$TMP" --strip-components=1
SRC="$TMP"

# --- Install packages ---
echo "Installing packages..."
apk update
apk add $(tr '\n' ' ' < "$SRC/packages")

# --- Set hostname ---
echo "mountbox" > /etc/hostname
hostname mountbox

# --- Copy configs (stamp version) ---
sed "s/%%VERSION%%/v${VERSION}/g" "$SRC/config/motd" > /etc/motd
sed "s/%%VERSION%%/v${VERSION}/g" "$SRC/config/issue" > /etc/issue

mkdir -p /etc/samba
cp "$SRC/config/smb.conf" /etc/samba/smb.conf

mkdir -p /etc/avahi/services
cp "$SRC/config/smb.service" /etc/avahi/services/smb.service

mkdir -p /etc/conf.d
cp "$SRC/config/consolefont" /etc/conf.d/consolefont

mkdir -p /etc/mountbox
sed "s/%%VERSION%%/v${VERSION}/g" "$SRC/config/mountbox/README.txt" > /etc/mountbox/README.txt

# Template: encryption key (do not overwrite existing)
if [ ! -f /etc/mountbox/encryption-key.txt ]; then
    cp "$SRC/config/mountbox/encryption-key.txt" /etc/mountbox/encryption-key.txt
    chmod 600 /etc/mountbox/encryption-key.txt
fi

# Template: authorized keys (do not overwrite existing)
if [ ! -f /etc/mountbox/authorized_keys ]; then
    cp "$SRC/config/mountbox/authorized_keys" /etc/mountbox/authorized_keys
    chmod 600 /etc/mountbox/authorized_keys
fi

mkdir -p /etc/ssh/sshd_config.d
cp "$SRC/config/sshd_mountbox.conf" /etc/ssh/sshd_config.d/mountbox.conf

# Ensure sshd_config includes drop-in directory (idempotent)
if ! grep -q '^Include /etc/ssh/sshd_config.d/\*.conf' /etc/ssh/sshd_config; then
    sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
fi

# --- Copy scripts ---
cp "$SRC/scripts/mount-sd" /usr/local/bin/mount-sd
cp "$SRC/scripts/umount-sd" /usr/local/bin/umount-sd
cp "$SRC/scripts/automount-sd" /usr/local/bin/automount-sd
cp "$SRC/scripts/update-mountbox" /usr/local/bin/update-mountbox
chmod +x /usr/local/bin/mount-sd /usr/local/bin/umount-sd /usr/local/bin/automount-sd /usr/local/bin/update-mountbox

# --- Add mdev rule (BEFORE persistent-storage block) ---
if ! grep -q 'automount-sd' /etc/mdev.conf; then
    if grep -q '^# persistent storage' /etc/mdev.conf; then
        sed -i '/^# persistent storage/i # removable storage\nsd[a-z][0-9]+   root:root 660 */usr/local/bin/automount-sd\n' /etc/mdev.conf
    else
        echo 'sd[a-z][0-9]+   root:root 660 */usr/local/bin/automount-sd' >> /etc/mdev.conf
    fi
fi

# --- Ensure /media exists ---
mkdir -p /media

# --- Enable services ---
rc-update add sshd default 2>/dev/null || true
rc-update add samba default 2>/dev/null || true
rc-update add avahi-daemon default 2>/dev/null || true
rc-update add consolefont boot 2>/dev/null || true

# --- Start services ---
rc-service samba start 2>/dev/null || rc-service samba restart
rc-service avahi-daemon start 2>/dev/null || rc-service avahi-daemon restart
rc-service sshd start 2>/dev/null || rc-service sshd restart
rc-service consolefont start 2>/dev/null || true

# --- Stamp installed version ---
echo "$VERSION" > "$VERSION_FILE"

echo ""
echo "=== MountBox v${VERSION} setup complete ==="
echo "Hostname: mountbox"
echo "Samba shares: Media (/media), Config (/etc/mountbox)"
echo "Connect from Finder: smb://mountbox.local/Media"
echo ""
