#!/bin/bash

# =================================================================
# VICHAN BORG RESTORE SCRIPT
# Restores a Vichan site from a specified Borg backup archive.
# WARNING: This script is DESTRUCTIVE and will overwrite your live site.
# =================================================================

# --- CONFIGURE YOUR SETTINGS HERE ---
# These must match your live Vichan setup.

# Database Credentials
DB_USER="your_db_user"
DB_PASS="your_db_password"
DB_NAME="your_db_name"

# The full path to your Vichan installation's root directory.
VICHAN_PATH="/var/www/your-site.com"

# The user your web server runs as (e.g., 'www-data' on Debian/Ubuntu).
WEB_USER="www-data"

# --- BORG CONFIGURATION ---
# The script will use these variables to connect to your repository.

# The full SSH URL to your Borg repository on the Raspberry Pi.
export BORG_REPO="ssh://pi@raspberrypi.local/path/to/your/borg_repo"

# The passphrase for your Borg repository.
# You will be prompted for this when the script runs.
# For manual use, it's safer to be prompted than to store it here.
# export BORG_PASSPHRASE="your_super_secret_borg_passphrase"

# --- END OF CONFIGURATION ---

# Exit immediately if a command exits with a non-zero status.
set -e

# --- SAFETY CHECKS ---

# 1. Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
   echo "This script is destructive and must be run as root. Please use sudo." >&2
   exit 1
fi

# 2. Check for archive name argument
if [ -z "$1" ]; then
  echo "Usage: sudo $0 <archive_name>"
  echo "Example: sudo $0 vichan-2025-06-13T13:44:46"
  echo "You can find archive names by running 'borg list \$BORG_REPO'"
  exit 1
fi

ARCHIVE_TO_RESTORE=$1

# 3. FINAL WARNING AND CONFIRMATION
echo -e "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo -e "!!                      W A R N I N G                     !!"
echo -e "!!                                                        !!"
echo -e "!!  This script will PERMANENTLY WIPE your current      !!"
echo -e "!!  database '$DB_NAME' and overwrite all files in !!"
echo -e "!!  '$VICHAN_PATH'.                                       !!"
echo -e "!!                                                        !!"
echo -e "!!  You are about to restore the following archive:       !!"
echo -e "!!  $ARCHIVE_TO_RESTORE"
echo -e "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"
read -p "Type 'YES' to proceed with the restoration: " CONFIRMATION

if [ "$CONFIRMATION" != "YES" ]; then
  echo "Restore cancelled by user."
  exit 0
fi

# --- RESTORATION LOGIC ---

# Create a secure temporary directory to work in.
TEMP_DIR=$(mktemp -d)

# This 'trap' command ensures the temporary directory is cleaned up when the script exits,
# even if it fails partway through.
trap 'echo "Cleaning up temporary files..."; rm -rf "$TEMP_DIR"' EXIT

echo -e "\n--- Starting Restore Process ---"

# Step 1: Extract the backup archive into the temporary directory.
echo "Step 1/5: Extracting archive '$ARCHIVE_TO_RESTORE'..."
# Borg will prompt for the repository passphrase here if the variable is not set.
borg extract "$BORG_REPO::$ARCHIVE_TO_RESTORE" --path "$TEMP_DIR"

# Find the full path to the extracted web root and database dump.
# Note: The paths inside the archive reflect the original backup paths.
EXTRACTED_VICHAN_PATH=$(find "$TEMP_DIR" -type d -path "*/$(basename $VICHAN_PATH)" | head -n 1)
DB_DUMP_FILE=$(find "$TEMP_DIR" -type f -name "db_dump.sql" | head -n 1)

if [ -z "$EXTRACTED_VICHAN_PATH" ] || [ -z "$DB_DUMP_FILE" ]; then
    echo "ERROR: Could not find extracted site files or database dump in the archive."
    exit 1
fi

# Step 2: Replace the live site files.
echo "Step 2/5: Replacing live site files..."
BROKEN_BACKUP_PATH="${VICHAN_PATH}_broken_$(date +%F_%T)"
echo "Moving current installation to '$BROKEN_BACKUP_PATH'..."
mv "$VICHAN_PATH" "$BROKEN_BACKUP_PATH"
echo "Moving restored files into place..."
mv "$EXTRACTED_VICHAN_PATH" "$VICHAN_PATH"

# Step 3: Restore the database.
echo "Step 3/5: Restoring the database..."
echo "Dropping and re-creating database '$DB_NAME'..."
mysql -u "$DB_USER" --password="$DB_PASS" -e "DROP DATABASE IF EXISTS \`$DB_NAME\`; CREATE DATABASE \`$DB_NAME\`;"
echo "Importing data from SQL dump..."
mysql -u "$DB_USER" --password="$DB_PASS" "$DB_NAME" < "$DB_DUMP_FILE"

# Step 4: Set correct file permissions for the web server.
echo "Step 4/5: Setting file permissions..."
chown -R "$WEB_USER":"$WEB_USER" "$VICHAN_PATH"

# Step 5: Finalization is handled by the 'trap' command which will clean up TEMP_DIR.
echo "Step 5/5: Cleanup of temporary extraction files is complete."

echo ""
echo "------------------------------------"
echo "✅ RESTORATION COMPLETE! ✅"
echo "------------------------------------"
echo "Your site has been restored from '$ARCHIVE_TO_RESTORE'."
echo "The previous (broken) site files are saved at: $BROKEN_BACKUP_PATH"
echo "Please verify the site is working and then manually delete that directory to save space."
echo "Command to delete: sudo rm -rf $BROKEN_BACKUP_PATH"

exit 0