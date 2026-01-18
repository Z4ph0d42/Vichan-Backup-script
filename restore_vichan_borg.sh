#!/bin/bash

# =================================================================
# VICHAN RESTORE SCRIPT (Fortress Edition)
# Restores: Database & Site Files.
# Extracts: Nginx & Fail2Ban configs for manual review (Safety).
# =================================================================

# --- 1. SETTINGS ---
# Borg Repository Path
BORG_REPO="ssh://user@backup_server/path/to/repo"

# Live Site Paths
VICHAN_PATH="/var/www/netherchan.org"
DB_NAME="vichan_db"
DB_USER="vichan_user"

# =================================================================

if [ -z "$1" ]; then
    echo "Usage: sudo $0 <archive_name>"
    echo "Example: sudo $0 2026-01-16-1819"
    echo "List archives: borg list $BORG_REPO"
    exit 1
fi

ARCHIVE="$1"

echo "!!! WARNING !!!"
echo "1. This will DELETE current files in $VICHAN_PATH"
echo "2. This will DROP and replace database $DB_NAME"
echo "3. Configs (Nginx/Fail2Ban) will be extracted to /root/ for review."
read -p "Type 'RESTORE' to continue: " CONFIRM

if [ "$CONFIRM" != "RESTORE" ]; then
    echo "Aborted."
    exit 0
fi

# 1. Setup Temp
TEMP_DIR=$(mktemp -d)
echo "--> Extracting $ARCHIVE..."

# 2. Extract
borg extract "$BORG_REPO::$ARCHIVE" --path "$TEMP_DIR"

if [ $? -ne 0 ]; then
    echo "❌ Extract failed."
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 3. Restore Database
echo "--> Restoring Database..."
SQL_FILE=$(find "$TEMP_DIR" -name "*.sql" | head -n 1)

if [ -f "$SQL_FILE" ]; then
    mysql -u "$DB_USER" -e "DROP DATABASE IF EXISTS $DB_NAME; CREATE DATABASE $DB_NAME;"
    mysql -u "$DB_USER" "$DB_NAME" < "$SQL_FILE"
    echo "✅ Database restored."
else
    echo "⚠️  No SQL file found in archive!"
fi

# 4. Restore Site Files
echo "--> Restoring Website Files..."
EXTRACTED_WEB="$TEMP_DIR$VICHAN_PATH"

if [ -d "$EXTRACTED_WEB" ]; then
    rm -rf "$VICHAN_PATH"/*
    cp -r "$EXTRACTED_WEB/." "$VICHAN_PATH/"
    chown -R www-data:www-data "$VICHAN_PATH"
    echo "✅ Website files restored."
else
    echo "⚠️  Website files not found at expected path: $EXTRACTED_WEB"
fi

# 5. Handle Configs (Nginx / Fail2Ban)
echo "--> Handling System Configs..."
CONFIG_RESTORE_DIR="/root/restored_configs_$(date +%F_%H%M)"
mkdir -p "$CONFIG_RESTORE_DIR"

if [ -d "$TEMP_DIR/etc" ]; then
    cp -r "$TEMP_DIR/etc" "$CONFIG_RESTORE_DIR/"
    echo "✅ Config files extracted to: $CONFIG_RESTORE_DIR"
    echo "   Action: Manually review these before overwriting /etc/."
else
    echo "ℹ️  No /etc configs found."
fi

# Cleanup
rm -rf "$TEMP_DIR"
echo "=========================================="
echo "RESTORE COMPLETE."