MountBox v1.0.0
===============

To enable automatic unencryption, create a file called
"encryption-key.txt" in this folder containing the encryption passphrase.

The file should contain only the passphrase, nothing else.

You can create this file from Finder:
  1. Connect to smb://mountbox.local/Config
  2. Create a new text file called "encryption-key.txt"
  3. Paste your LUKS passphrase and save

Security note: The passphrase is stored in plaintext in the VM.
Anyone with access to your Mac and the UTM VM file could read it.
