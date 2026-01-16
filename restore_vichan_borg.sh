#!/bin/bash

# =================================================================
# VICHAN RESTORE SCRIPT (BorgBackup)
# -----------------------------------------------------------------
# Description: Restores Database & Site Files from a Borg Archive.
# Safety: Config files (Nginx/Fail2Ban) are extracted to a temp 
#         folder for manual review, never overwriting /etc directly.
# =================================================================

# --- 1. USER CONFIGURATION (EDIT BEFORE RUNNING) ---

# Borg Repository Location
# Example: ssh://user@192.168.1.50/mnt/backups/vichan
BORG_REPO="ssh://user@backup_host/path/to/repo"

# Live Site Configuration
VICHAN_PATH="/var/www/html"   # Where your live board lives
DB_NAME="vichan"              # Database name to overwrite
DB_USER="vichan_user"         # Database user
WEB_USER="www-data"           # Web server user (usually www-data)

# =================================================================

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (sudo)."
  exit 1
fi

# Check for Archive Name argument
if [ -z "$1" ]; then
    echo "Usage: $0 <archive_name>"
    echo "Example: $0 vichan-2026-01-15-0400"
    echo "-----------------------------------------------------"
    echo "To list available archives, run:"
    echo "borg list $BORG_REPO"
    exit 1
fi

ARCHIVE="$1"

echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!!!                   W A R N I N G                       !!!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "This script acts DESTRUCTIVELY on the live environment:"
echo "1. It will DELETE all current files in $VICHAN_PATH"
echo "2. It will DROP and replace database '$DB_NAME'"
echo ""
echo "System configs (Nginx/Fail2Ban) found in the backup will"
echo "be extracted to /root/restored_configs/ for safety."
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo ""
read -p "Type 'RESTORE' to confirm and proceed: " CONFIRM

if [ "$CONFIRM" != "RESTORE" ]; then
    echo "Aborted by user."
    exit 0
fi

# 1. Create Secure Temp Directory
TEMP_DIR=$(mktemp -d)
echo "--> Extracting archive '$ARCHIVE' to temporary workspace..."
echo "(Please enter Borg passphrase if prompted)"

# 2. Extract Archive
# Note: Borg extracts paths relative to how they were backed up (usually absolute paths)
borg extract "$BORG_REPO::$ARCHIVE" --path "$TEMP_DIR"

if [ $? -ne 0 ]; then
    echo "❌ Extract failed. Check passphrase or connectivity."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 3. Restore Database
echo "--> Restoring Database..."
# Find any .sql file in the temp dir
SQL_FILE=$(find "$TEMP_DIR" -name "*.sql" | head -n 1)

if [ -f "$SQL_FILE" ]; then
    echo "    Found dump: $SQL_FILE"
    # Recreating database ensures a clean slate
    mysql -u "$DB_USER" -e "DROP DATABASE IF EXISTS $DB_NAME; CREATE DATABASE $DB_NAME;"
    mysql -u "$DB_USER" "$DB_NAME" < "$SQL_FILE"
    echo "✅ Database restored successfully."
else
    echo "⚠️  CRITICAL: No SQL dump found in this archive!"
fi

# 4. Restore Site Files
echo "--> Restoring Website Files..."
# Look for the web root inside the extracted folders
EXTRACTED_WEB="$TEMP_DIR$VICHAN_PATH"

if [ -d "$EXTRACTED_WEB" ]; then
    # Clear live directory
    rm -rf "${VICHAN_PATH:?}"/*
    
    # Copy restored files
    cp -r "$EXTRACTED_WEB/." "$VICHAN_PATH/"
    
    # Fix Permissions
    chown -R "$WEB_USER":"$WEB_USER" "$VICHAN_PATH"
    echo "✅ Website files restored to $VICHAN_PATH"
else
    echo "⚠️  Website path not found in archive. Expected: $EXTRACTED_WEB"
    echo "    Manual intervention may be required to move files."
fi

# 5. Handle Configs (Nginx / Fail2Ban / System)
echo "--> Handling System Configurations..."
RESTORE_DATE=$(date +%F_%H%M)
CONFIG_RESTORE_DIR="/root/restored_configs_$RESTORE_DATE"
mkdir -p "$CONFIG_RESTORE_DIR"

if [ -d "$TEMP_DIR/etc" ]; then
    cp -r "$TEMP_DIR/etc" "$CONFIG_RESTORE_DIR/"
    echo "✅ /etc/ configuration files extracted to: $CONFIG_RESTORE_DIR"
    echo "   NOTE: We do not overwrite /etc/ automatically."
    echo "   Please manually compare your current Nginx/Fail2Ban configs"
    echo "   with the restored versions in this folder."
else
    echo "ℹ️  No system configs (/etc) found in this backup."
fi

# 6. Cleanup
echo "--> Cleaning up temporary files..."
rm -rf "$TEMP_DIR"

echo ""
echo "=========================================="
echo "      RESTORE OPERATION COMPLETE"
echo "=========================================="