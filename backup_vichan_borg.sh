#!/bin/bash
# FINAL WORKING VERSION - v3.0

# --- CONFIGURATION ---
DB_USER="vichan"
DB_PASS="Password"
DB_NAME="vichan_db"
VICHAN_PATH="path"
BOT_PATH="path"

export BORG_REPO="path"
export BORG_KEY_FILE="key"
export BORG_PASSPHRASE="Password"
# --- END OF CONFIGURATION ---

set -e
echo "--- Starting Borg Backup Process $(date) ---"

# Step 1: Dump the database
echo "Step 1/3: Dumping database..."
DB_DUMP_FILE="/tmp/vichan_db_dump.sql"
mysqldump -u "$DB_USER" --password="$DB_PASS" --single-transaction "$DB_NAME" > "$DB_DUMP_FILE"

# Step 2: Create the Borg backup archive
echo "Step 2/3: Creating Borg archive..."
borg create \
    --verbose \
    --stats \
    --progress \
    --compression lz4 \
    --exclude-from "$BOT_PATH/.borgignore" \
    ::'vichan-{now}' \
    "$VICHAN_PATH" \
    "$DB_DUMP_FILE" \
    "$BOT_PATH"

# Step 3: Prune old backups and clean up
echo "Step 3/3: Pruning and cleaning up..."
borg prune -v --list --keep-daily=7 --keep-weekly=4 --keep-monthly=6
rm "$DB_DUMP_FILE"

echo "------------------------------------"
echo "✅ Borg Backup and Prune Complete! ✅"
echo "------------------------------------"

exit 0
