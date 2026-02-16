MountBox %%VERSION%%
===============

SSH Access
----------
To enable SSH access, create a file called "authorized_keys" in this
folder containing your SSH public key.

  1. On your Mac, copy your public key:
       cat ~/.ssh/id_ed25519.pub | pbcopy
  2. In this folder, create a file called "authorized_keys"
  3. Paste the key and save

Then connect: ssh root@mountbox.local

LUKS Encryption
---------------
To enable automatic decryption, create a file called
"encryption-key.txt" in this folder containing the encryption passphrase.

The file should contain only the passphrase, nothing else.

Security note: Files in this folder are stored in plaintext in the VM.
Anyone with access to your Mac and the VM file could read them.
