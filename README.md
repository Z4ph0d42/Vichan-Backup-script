
# Vichan Backup and Restore script

This project provides a robust, secure, and automated solution for creating backups of a Vichan imageboard. It uses BorgBackup to create space-efficient, encrypted, and deduplicated backups and transfers them to a secondary machine on your local network, such as a Raspberry Pi.

This solution is designed for server administrators who want a "set it and forget it" system that protects against data loss from application errors, database corruption, or server hardware failure.

Features:


Complete Snapshot: Backs up the entire MariaDB/MySQL database and all user-uploaded files and themes.

Fully Automated: Uses cron for scheduled backups without requiring any user interaction.

Secure: Employs end-to-end encryption. Data is encrypted both in transit (via SSH) and at rest (via Borg's repository encryption).

Highly Space-Efficient: Utilizes BorgBackup's block-level deduplication for fast, small incremental backups. Only new data is transferred after the initial backup.

Intelligent Retention: Automatically prunes old backups using a flexible daily, weekly, and monthly retention schedule to manage long-term storage space.

Off-Site LAN Storage: Transfers backups to a secondary machine on the local network for protection against primary server failure.

Resilient and Verifiable: Built on Borg's chunk-based architecture, which is resistant to backup chain corruption and allows for full data integrity checks.

**Prerequisites**

1. A running Vichan instance on a Debian-based server (e.g., Debian, Ubuntu).
2. A secondary Linux machine on the same local network to act as the backup server (a Raspberry Pi is perfect for this).
3. sudo access on both machines.
4. BorgBackup installed on both machines. You can install it with: sudo apt update && sudo apt install borgbackup.



## Installation

**Step 1: On the Backup Server (e.g., Raspberry Pi)**

First, we need to create the secure backup location.

Prepare the Repository Directory This step creates the folder for the backups and gives your user the correct permissions to write to it.
Replace 'pi' with your actual username if it is different.
Replace the path with the location where you want to store the backups.
```bash
  sudo mkdir -p /path/to/your/borg_repo sudo chown pi:pi /path/to/your/borg_repo
```
**Step 2: Initialize the Borg Repository**
This command creates the encrypted repository. This is a one-time setup.
On your Backup Server:
```bash
    borg init --encryption=repokey /path/to/your/borg_repo
```
Borg will prompt you to create a new passphrase. This is the master password for your entire backup set.  ***Choose a strong passphrase and save it securely in a password manager. If you lose this passphrase, your backups are unrecoverable.***

**Step 3: Export the Repository Key**

To allow for automated backups, we need to export the repository's key.
On your Backup Server:
This will create a key file in your home directory.
```bash
    borg key export /path/to/your/borg_repo ~/exported_borg_key
```
Borg will ask for the passphrase you just created to authorize this export.

**Step 4: Configure the Vichan Server**

Now, we will set up the server that hosts your imageboard.
On your Vichan Server:
1. Copy the Repository Key:
Use scp to securely copy the key file from the backup server.
 Replace 'pi@raspberrypi.local' with your backup server's user and hostname/IP.
 This will ask for your backup server user's password.
```bash
    scp pi@raspberrypi.local:~/exported_borg_key ~/.config/borg/repo.key
```
2. Enable Passwordless SSH Login:
For cron to run the script automatically, your Vichan server must be able to log into the backup server without a password.
```bash
# First, generate a key if you don't have one. Press Enter at all prompts.
ssh-keygen
# Now, copy the new key to your backup server.
# This will ask for your backup server user's password one last time.
ssh-copy-id pi@raspberrypi.local
```
3. Create the Backup Script
Create a new file for the backup script logic.
```bash
    nano $HOME/backup_vichan_borg.sh
```
Copy the entire contents of the backup_vichan_borg.sh script into this file. Edit the "CONFIGURE YOUR SETTINGS HERE" section at the top with your specific database credentials, paths, and passphrase.
4. Make the Script Executable
```bash
    chmod +x $HOME/backup_vichan_borg.sh
```
**Step 3: Automation and Final Test**

1. Run a Manual Test
Execute the script manually to ensure everything is configured correctly.
```bash
    $HOME/backup_vichan_borg.sh
```
The first run will be slow as it uploads all data. Subsequent runs will be much faster.
2. Schedule with Cron
Once the test is successful, schedule the script to run automatically.
```bash
    crontab -e
```
Add the following line to the end of the file to schedule a backup for 2:00 AM every night. 
Replace your_user with your username on the Vichan server.
```bash
    0 2 * * * /bin/bash /home/your_user/backup_vichan_borg.sh > /home/your_user/borg_backup_log.txt 2>&1
```
## Restore Instructions
1. Create the Restore Script
```bash
# Create the script file
nano $HOME/restore_vichan_borg.sh

# Make it executable
chmod +x $HOME/restore_vichan_borg.sh
```
Copy the entire contents of the restore_vichan_borg.sh script into this file. Edit the configuration section to match your setup.

2. List Available Backups
First, find the exact "point in time" you want to restore.
```bash
# Set the BORG_REPO variable to your repository path
export BORG_REPO="ssh://pi@raspberrypi.local/path/to/your/borg_repo"
borg list
```
This will show a list of all available archives. Copy the name of the one you wish to restore (e.g., vichan-2025-06-13T13:44:46).

3. Run the Restore Script
Execute the script with sudo, providing the archive name as an argument.
```bash
# WARNING: This is a destructive action.
sudo $HOME/restore_vichan_borg.sh vichan-2025-06-13T13:44:46
```
