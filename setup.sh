#!/bin/sh
set -e

echo "=== MountBox Setup ==="
echo "Configuring Alpine Linux as a USB mount server..."
echo ""

# --- Install packages ---
echo "Installing packages..."
apk update
apk add cryptsetup e2fsprogs samba usbutils avahi blkid terminus-font

# --- Set hostname ---
echo "mountbox" > /etc/hostname
hostname mountbox

# --- Write /etc/motd ---
cat > /etc/motd << 'EOF'
Welcome to
  __  __                   _   ____
 |  \/  | ___  _   _ _ __ | |_| __ )  _____  __
 | |\/| |/ _ \| | | | '_ \| __|  _ \ / _ \ \/ /
 | |  | | (_) | |_| | | | | |_| |_) | (_) >  <
 |_|  |_|\___/ \__,_|_| |_|\__|____/ \___/_/\_\
EOF

# --- Write /etc/issue (backslashes doubled for agetty) ---
cat > /etc/issue << 'EOF'
   __  __                   _   ____
  |  \\/  | ___  _   _ _ __ | |_| __ )  _____  __
  | |\\/| |/ _ \\| | | | '_ \\| __|  _ \\ / _ \\ \\/ /
  | |  | | (_) | |_| | | | | |_| |_) | (_) >  <
  |_|  |_|\\___/ \\__,_|_| |_|\\__|____/ \\___/_/\\_\\
- How to use ------------------------------------
  1. Plug USB device into Mac
  2. Click "Ignore" on macOS disk prompt
  3. UTM toolbar > USB icon > attach device
  Finder > Network > mountbox > Media
  or Cmd+K > smb://mountbox.local/Media
  To disconnect:
  1. Eject Media share in Finder
  2. Detach USB in UTM toolbar
  3. Remove device
-------------------------------------------------
EOF

# --- Write Samba config ---
mkdir -p /etc/samba
cat > /etc/samba/smb.conf << 'EOF'
[global]
  workgroup = WORKGROUP
  security = user
  map to guest = Bad Password
  log level = 1
  vfs objects = fruit
  fruit:model = TimeCapsule6,116

[Media]
  path = /media
  browseable = yes
  writable = yes
  guest ok = yes
  force user = root
  create mask = 0644
  directory mask = 0755
  veto files = /cdrom/usb/floppy/

[Config]
  path = /etc/mountbox
  browseable = yes
  writable = yes
  guest ok = yes
  force user = root
  create mask = 0600
  directory mask = 0700
EOF

# --- Write Avahi SMB service ---
mkdir -p /etc/avahi/services
cat > /etc/avahi/services/smb.service << 'EOF'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>
</service-group>
EOF

# --- Write console font config ---
mkdir -p /etc/conf.d
cat > /etc/conf.d/consolefont << 'EOF'
consolefont="ter-v16b.psf.gz"
EOF

# --- Create /etc/mountbox with README ---
mkdir -p /etc/mountbox
cat > /etc/mountbox/README.txt << 'EOF'
MountBox Configuration
======================

To enable automatic unencryption, create a file called
"encryption-key.txt" in this folder containing the encryption passphrase.

The file should contain only the passphrase, nothing else.

You can create this file from Finder:
  1. Connect to smb://mountbox.local/Config
  2. Create a new text file called "encryption-key.txt"
  3. Paste your LUKS passphrase and save

Security note: The passphrase is stored in plaintext in the VM.
Anyone with access to your Mac and the UTM VM file could read it.
EOF

# --- Install scripts ---
cat > /usr/local/bin/mount-sd << 'SCRIPT'
#!/bin/sh
set -e

SD_DEV="${1:-/dev/sda1}"
DEV_NAME="$(basename "$SD_DEV")"
LUKS_NAME="luks_${DEV_NAME}"
PASSPHRASE_FILE="/etc/mountbox/encryption-key.txt"
BASE_DIR="/media"
MOUNT_DEV="$SD_DEV"

# Unlock LUKS if needed
if cryptsetup isLuks "$SD_DEV" 2>/dev/null; then
    if [ ! -e "/dev/mapper/$LUKS_NAME" ]; then
        # Save passphrase if provided as second argument
        if [ -n "$2" ]; then
            echo -n "$2" > "$PASSPHRASE_FILE"
            chmod 600 "$PASSPHRASE_FILE"
            echo "Passphrase saved to $PASSPHRASE_FILE"
        fi

        if [ -f "$PASSPHRASE_FILE" ] && \
           cryptsetup luksOpen "$SD_DEV" "$LUKS_NAME" --key-file "$PASSPHRASE_FILE" 2>/dev/null; then
            echo "LUKS auto-unlocked on $SD_DEV"
        else
            echo "Error: LUKS device $SD_DEV cannot be unlocked."
            echo "No passphrase stored or passphrase didn't match."
            echo "Create encryption-key.txt in the Config share, or run:"
            echo "  mount-sd $SD_DEV <passphrase>"
            exit 1
        fi
    fi
    MOUNT_DEV="/dev/mapper/$LUKS_NAME"
fi

# Use filesystem label if available, otherwise device name
LABEL="$(blkid -s LABEL -o value "$MOUNT_DEV" 2>/dev/null | tr ' /' '_-')"
MOUNT_NAME="${LABEL:-$DEV_NAME}"
MOUNT_POINT="${BASE_DIR}/${MOUNT_NAME}"

mkdir -p "$MOUNT_POINT"
mount -t auto "$MOUNT_DEV" "$MOUNT_POINT"
echo "Mounted at $MOUNT_POINT"
SCRIPT
chmod +x /usr/local/bin/mount-sd

cat > /usr/local/bin/umount-sd << 'SCRIPT'
#!/bin/sh
set -e

SD_DEV="${1:-/dev/sda1}"
DEV_NAME="$(basename "$SD_DEV")"
LUKS_NAME="luks_${DEV_NAME}"
BASE_DIR="/media"

# Find mount point for this device
MOUNT_DEV="$SD_DEV"
[ -e "/dev/mapper/$LUKS_NAME" ] && MOUNT_DEV="/dev/mapper/$LUKS_NAME"

MOUNT_POINT="$(mount | grep "^$MOUNT_DEV " | awk '{print $3}')"

if [ -n "$MOUNT_POINT" ]; then
    umount "$MOUNT_POINT" 2>/dev/null || true
    rmdir "$MOUNT_POINT" 2>/dev/null || true
    echo "Unmounted $MOUNT_POINT"
fi

if [ -e "/dev/mapper/$LUKS_NAME" ]; then
    cryptsetup luksClose "$LUKS_NAME"
    echo "LUKS closed."
fi
SCRIPT
chmod +x /usr/local/bin/umount-sd

cat > /usr/local/bin/automount-sd << 'SCRIPT'
#!/bin/sh
DEV="/dev/${MDEV}"

case "$ACTION" in
  add)
    /usr/local/bin/mount-sd "$DEV" 2>&1 | logger -t automount
    ;;
  remove)
    /usr/local/bin/umount-sd "$DEV" 2>&1 | logger -t automount
    ;;
esac
SCRIPT
chmod +x /usr/local/bin/automount-sd

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
rc-update add samba default
rc-update add avahi-daemon default
rc-update add consolefont boot

# --- Start services ---
rc-service samba start
rc-service avahi-daemon start
rc-service consolefont start

echo ""
echo "=== MountBox setup complete ==="
echo "Hostname: mountbox"
echo "Samba shares: Media (/media), Config (/etc/mountbox)"
echo "Connect from Finder: smb://mountbox.local/Media"
echo ""
