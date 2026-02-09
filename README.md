# MountBox

Minimal Alpine Linux aarch64 VM for [UTM](https://mac.getutm.app) on macOS Apple Silicon that auto-mounts ext4 and LUKS-encrypted USB devices and exposes them to Finder via Samba.

## Why

macOS cannot read ext4 or LUKS volumes. Commercial solutions exist but they're heavy, require kernel extensions, and often lag behind macOS releases.
MountBox takes a different approach: a tiny (~200 MB) Alpine Linux VM handles the filesystems natively and shares them back to your Mac over SMB.
Plug in a drive, and it shows up in Finder - no drivers, no FUSE, no kernel extensions.

## Features

- **Auto-mount** — USB devices are detected and mounted automatically via mdev
- **LUKS support** — encrypted drives unlock automatically with a stored passphrase
- **Finder integration** — browse files via SMB at `smb://mountbox.local/Media`
- **Bonjour discovery** — the VM advertises itself as `mountbox.local` via Avahi
- **Time Capsule icon** — appears as a Time Capsule in Finder sidebar (fruit VFS)
- **Config share** — manage LUKS passphrases from Finder at `smb://mountbox.local/Config`
- **Tiny footprint** — ~200 MB disk, 512 MB RAM, boots in seconds with Apple Hypervisor
- **No kernel extensions** — runs entirely in userspace via UTM/QEMU

## Prerequisites

- macOS on Apple Silicon (M1/M2/M3/M4)
- [UTM](https://mac.getutm.app) installed (free, open source)
- USB card reader or USB storage device

## Quick Start

### Option A: Pre-built VM (Releases)

1. Download the latest `.utm` bundle from [Releases](../../releases)
2. Double-click to import into UTM
3. Start the VM
4. Plug in your USB device, click **Ignore** on the macOS disk prompt
5. In UTM toolbar, click the USB icon and attach your device
6. Open Finder → Network → **mountbox** → **Media**

### Option B: Build from Scratch

See [Manual Setup](#manual-setup) below.

## Manual Setup

### 1. Create the UTM VM

Open UTM and create a new VM with these settings:

| Setting | Value |
|---------|-------|
| Type | Emulate |
| Architecture | ARM64 (aarch64) |
| System | QEMU ARM Virtual Machine |
| RAM | 512 MB |
| Storage | 1 GB |
| Boot | UEFI |
| Network | Shared Network |
| USB | USB 3.0 (XHCI) |
| Display | virtio-gpu-pci |
| Hypervisor | Enabled (Use Apple Virtualization) |

### 2. Install Alpine Linux

1. Download [Alpine Linux Virtual aarch64 ISO](https://alpinelinux.org/downloads/)
2. Mount the ISO in UTM and boot the VM
3. Log in as `root` (no password)
4. Run `setup-alpine` and follow the prompts:
   - Keyboard: `us` / `us`
   - Hostname: `mountbox`
   - Network: `eth0`, DHCP
   - Root password: set one you'll remember
   - Timezone: your timezone
   - Disk: `vda`, `sys` mode
5. Reboot and remove the ISO

### 3. Run the Setup Script

SSH into the VM and run the setup script:

```sh
ssh root@mountbox.local 'sh -s' < setup.sh
```

Or clone and pipe:

```sh
git clone https://github.com/user/mountbox.git
cd mountbox
ssh root@mountbox.local 'sh -s' < setup.sh
```

The script installs all packages, configures Samba, Avahi, mdev automounting, and sets up the LUKS passphrase management system.

## Daily Usage

### Mounting a USB Device

1. Plug the USB device into your Mac
2. Click **Ignore** when macOS asks about the unreadable disk
3. In UTM toolbar, click the **USB icon** → attach your device
4. Open Finder → Network → **mountbox** → **Media**
   - Or press **Cmd+K** and enter `smb://mountbox.local/Media`

### Unmounting

1. Eject the **Media** share in Finder
2. In UTM toolbar, click the **USB icon** → detach the device
3. Physically remove the USB device

### Manual Mount/Unmount

SSH into the VM:

```sh
# Mount
mount-sd /dev/sda1

# Unmount
umount-sd /dev/sda1
```

## LUKS Encrypted Drives

MountBox supports LUKS-encrypted drives. There are three ways to provide the passphrase:

### Option 1: Config Share (Recommended)

1. In Finder, press **Cmd+K** and connect to `smb://mountbox.local/Config`
2. Create a file called `encryption-key.txt`
3. Paste your LUKS passphrase and save
4. Future USB insertions will auto-unlock using this passphrase

### Option 2: Command Line

```sh
ssh root@mountbox.local
mount-sd /dev/sda1 "your-passphrase"
```

This mounts the drive and saves the passphrase for future use.

### Option 3: Interactive

```sh
ssh root@mountbox.local
cryptsetup luksOpen /dev/sda1 luks_sda1
mount /dev/mapper/luks_sda1 /media/sda1
```

> [!WARNING]
> The passphrase is stored in plaintext inside the VM.
> Anyone with access to your Mac and the UTM VM file can read it.

## UTM VM Settings Reference

The `utm/` directory is a placeholder for your VM's `config.plist`. To export it:

1. In UTM, right-click the VM → **Show in Finder**
2. Right-click the `.utm` bundle → **Show Package Contents**
3. Copy `config.plist` to `utm/config.plist`

This is useful for version-controlling your VM configuration or sharing it with others.

## Troubleshooting

> [!TIP]
> All system and automount logs are in the BusyBox syslog ring buffer.
> Run `logread` to view them, or `logread -f` to follow in real time.

### VM doesn't appear in Finder sidebar

- Make sure Avahi is running: `rc-service avahi-daemon status`
- Check the SMB service file exists: `ls /etc/avahi/services/smb.service`
- Try connecting directly: **Cmd+K** → `smb://mountbox.local/Media`

### USB device not detected

- Ensure USB support is enabled in UTM VM settings (USB 3.0 XHCI)
- Check that you attached the device in UTM toolbar (USB icon)
- Verify the device is visible: `lsusb` and `lsblk` in the VM
- Check mdev logs: `logread | grep automount`

### Drive doesn't auto-mount

- Check the mdev rule exists: `grep automount /etc/mdev.conf`
- Ensure the automount rule is BEFORE the persistent-storage line
- Try mounting manually: `mount-sd /dev/sda1`

### LUKS drive won't unlock

- Verify the passphrase file: `cat /etc/mountbox/encryption-key.txt`
- Check the device is LUKS: `cryptsetup isLuks /dev/sda1 && echo yes`
- Try unlocking manually: `cryptsetup luksOpen /dev/sda1 luks_sda1`

### Cannot connect via SSH

- Verify the VM's IP: check UTM's network info or run `ip addr` on the VM console
- Try connecting by IP: `ssh root@<vm-ip>`
- Ensure sshd is running: `rc-service sshd status`

### Samba permission errors

- All shares use `guest ok = yes` with `force user = root` — no authentication needed
- If you see permission errors, restart Samba: `rc-service samba restart`

## Project Structure

```
mountbox/
├── README.md              # This file
├── CHANGELOG.md           # Version history
├── LICENSE                # MIT
├── .gitignore
├── setup.sh               # Post-install automation script
├── packages               # Alpine packages to install
├── scripts/
│   ├── mount-sd           # Mount a USB device (handles LUKS)
│   ├── umount-sd          # Unmount and close LUKS
│   └── automount-sd       # mdev handler for hot-plug events
├── config/
│   ├── smb.conf           # Samba configuration
│   ├── smb.service        # Avahi service for SMB discovery
│   ├── motd               # Login banner
│   ├── issue              # TTY login screen
│   ├── consolefont        # Console font configuration
│   └── mountbox/
│       └── README.txt     # Instructions in the Config share
└── utm/
    └── .gitkeep           # Placeholder for VM config.plist
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b my-feature`
3. Make your changes
4. Test by running `setup.sh` against a fresh Alpine VM
5. Submit a pull request

## License

[MIT](LICENSE)
