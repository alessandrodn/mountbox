#!/bin/sh
set -e

REPO="alessandrodn/mountbox"
VERSION="${VERSION:?Usage: VERSION=x.y.z sh setup.sh}"

echo "=== MountBox v${VERSION} Setup ==="
echo "Configuring Alpine Linux as a USB mount server..."
echo ""

# --- Download repo tarball ---
echo "Downloading MountBox v${VERSION}..."
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
wget -qO- "https://github.com/$REPO/archive/v${VERSION}.tar.gz" | tar xz -C "$TMP"
SRC="$TMP/mountbox-${VERSION}"

# --- Install packages ---
echo "Installing packages..."
apk update
apk add $(tr '\n' ' ' < "$SRC/packages")

# --- Set hostname ---
echo "mountbox" > /etc/hostname
hostname mountbox

# --- Copy configs ---
cp "$SRC/config/motd" /etc/motd
cp "$SRC/config/issue" /etc/issue

mkdir -p /etc/samba
cp "$SRC/config/smb.conf" /etc/samba/smb.conf

mkdir -p /etc/avahi/services
cp "$SRC/config/smb.service" /etc/avahi/services/smb.service

mkdir -p /etc/conf.d
cp "$SRC/config/consolefont" /etc/conf.d/consolefont

mkdir -p /etc/mountbox
cp "$SRC/config/mountbox/README.txt" /etc/mountbox/README.txt

# --- Copy scripts ---
cp "$SRC/scripts/mount-sd" /usr/local/bin/mount-sd
cp "$SRC/scripts/umount-sd" /usr/local/bin/umount-sd
cp "$SRC/scripts/automount-sd" /usr/local/bin/automount-sd
cp "$SRC/scripts/update-mountbox" /usr/local/bin/update-mountbox
chmod +x /usr/local/bin/mount-sd /usr/local/bin/umount-sd /usr/local/bin/automount-sd /usr/local/bin/update-mountbox

# --- Add mdev rule (BEFORE persistent-storage line) ---
if ! grep -q 'automount-sd' /etc/mdev.conf; then
    if grep -q 'sd\[a-z\]\..*persistent-storage' /etc/mdev.conf; then
        sed -i '/sd\[a-z\]\..*persistent-storage/i sd[a-z][0-9]+   root:root 660 */usr/local/bin/automount-sd' /etc/mdev.conf
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
rc-service consolefont start 2>/dev/null || true

echo ""
echo "=== MountBox v${VERSION} setup complete ==="
echo "Hostname: mountbox"
echo "Samba shares: Media (/media), Config (/etc/mountbox)"
echo "Connect from Finder: smb://mountbox.local/Media"
echo ""
