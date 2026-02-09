# MountBox

Minimal Alpine Linux VM that auto-mounts ext4 and LUKS-encrypted USB devices and exposes them to Finder via Samba.

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
- **Tiny footprint** — ~200 MB disk, 512 MB RAM, boots in seconds
- **Hypervisor agnostic** — works with UTM, VMware Fusion, Parallels, or any VM that runs Alpine Linux

## Prerequisites

- macOS (Apple Silicon or Intel)
- A hypervisor with **USB passthrough** support: [UTM](https://mac.getutm.app) (free), VMware Fusion, Parallels, or similar
- USB card reader or USB storage device

## Install

### 1. Create an Alpine Linux VM

Create a VM in your hypervisor of choice with these recommended settings:

| Setting | Value |
|---------|-------|
| Architecture | aarch64 (ARM) or x86_64 |
| RAM | 512 MB |
| Storage | 1 GB |
| Network | Shared / Bridged |
| USB | USB 3.0 (XHCI) passthrough |

Then install Alpine Linux:

1. Download the [Alpine Linux ISO](https://alpinelinux.org/downloads/) (Virtual edition matches your architecture)
2. Boot the VM from the ISO
3. Log in as `root` (no password)
4. Run `setup-alpine` and follow the prompts:
   - Keyboard: `us` / `us`
   - Hostname: `mountbox`
   - Network: `eth0`, DHCP
   - Root password: set one you'll remember
   - Timezone: your timezone
   - Disk: `vda`, `sys` mode
5. Reboot and remove the ISO

### 2. Install MountBox

Log into the VM console and run:

```sh
wget -qO- https://raw.githubusercontent.com/alessandrodn/mountbox/main/scripts/update-mountbox | sh
```

That's it. The script installs all packages, configures Samba, Avahi, mdev automounting, and sets up the LUKS passphrase management system.

## Update

From the VM (or via SSH):

```sh
update-mountbox
```

This fetches the latest release from GitHub and re-runs the setup.

## Daily Usage

### Mounting a USB Device

1. Plug the USB device into your Mac
2. Click **Ignore** when macOS asks about the unreadable disk
3. In your hypervisor, attach/pass through the USB device to the VM
4. Open Finder → Network → **mountbox** → **Media**
   - Or press **Cmd+K** and enter `smb://mountbox.local/Media`

### Unmounting

1. Eject the **Media** share in Finder
2. Detach the USB device in your hypervisor
3. Physically remove the USB device

### Manual Mount/Unmount

SSH into the VM:

```sh
# Mount
mount-sd /dev/sda1

# Unmount
umount-sd /dev/sda1
```

## SSH Access

By default MountBox is managed via the VM console. To enable SSH, drop your public key into the Config share:

1. In Finder, press **Cmd+K** and connect to `smb://mountbox.local/Config`
2. Create a file called `authorized_keys`
3. Paste the contents of your public key (e.g. `~/.ssh/id_ed25519.pub`) and save

Then connect:

```sh
ssh root@mountbox.local
```

sshd reads `authorized_keys` on every connection — no restart needed. Password login is disabled; only key-based auth is allowed.

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
> Anyone with access to your Mac and the VM file can read it.

## Troubleshooting

> [!TIP]
> All system and automount logs are in the BusyBox syslog ring buffer.
> Run `logread` to view them, or `logread -f` to follow in real time.

### VM doesn't appear in Finder sidebar

- Make sure Avahi is running: `rc-service avahi-daemon status`
- Check the SMB service file exists: `ls /etc/avahi/services/smb.service`
- Try connecting directly: **Cmd+K** → `smb://mountbox.local/Media`

### USB device not detected

- Ensure USB passthrough is enabled in your hypervisor's VM settings
- Check that you attached the device to the VM
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

- Ensure your public key is in the Config share: `cat /etc/mountbox/authorized_keys`
- Password login is disabled — only key-based auth works
- Verify the VM's IP: check your hypervisor's network info or run `ip addr` on the VM console
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
├── setup.sh               # Main setup script (downloads repo, copies files)
├── packages               # Alpine packages to install (one per line)
├── scripts/
│   ├── mount-sd           # Mount a USB device (handles LUKS)
│   ├── umount-sd          # Unmount and close LUKS
│   ├── automount-sd       # mdev handler for hot-plug events
│   └── update-mountbox    # Self-updater (fetches latest release)
├── config/
│   ├── smb.conf           # Samba configuration
│   ├── smb.service        # Avahi service for SMB discovery
│   ├── motd               # Login banner
│   ├── issue              # TTY login screen
│   ├── consolefont        # Console font configuration
│   ├── sshd_mountbox.conf # sshd drop-in (key-only root login)
│   └── mountbox/
│       └── README.txt     # Instructions in the Config share
└── utm/
    └── .gitkeep           # Placeholder for VM config
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b my-feature`
3. Make your changes
4. Test by running `setup.sh` against a fresh Alpine VM
5. Submit a pull request

## License

[MIT](LICENSE)
