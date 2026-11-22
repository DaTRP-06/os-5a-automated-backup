#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/tmp/backup_5a.lock"
LOG_FILE="logs/backup.log"
REPORT_FILE="output/laporan.txt"

mkdir -p logs output

# [MEMBER 5] Operational logging helper
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# [MEMBER 1] Parameter & source directory validation
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <source_dir> <dest_dir>" >&2
    exit 2
fi

SRC_DIR="$1"
DEST_DIR="$2"

if [ ! -d "$SRC_DIR" ] || [ -z "$(ls -A "$SRC_DIR" 2>/dev/null)" ]; then
    log_msg "ERROR: Source directory '$SRC_DIR' does not exist or is empty."
    exit 2
fi

# [MEMBER 5] Concurrency lock (Critical Section protection)
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log_msg "ERROR: Lock active ($LOCK_FILE). Another backup process is already running."
    exit 6
fi

# [MEMBER 2] Load config, check destination, create archive & apply permissions
if [ -f "config/backup.conf" ]; then
    source config/backup.conf
fi

if [ ! -d "$DEST_DIR" ] || [ ! -w "$DEST_DIR" ]; then
    log_msg "ERROR: Destination directory '$DEST_DIR' is not writable."
    exit "${EXIT_ERR_ARCHIVE:-3}"
fi

chmod "${DIR_MODE:-750}" "$DEST_DIR" 2>/dev/null || true

TIMESTAMP=$(date "+${TIMESTAMP_FORMAT:-%Y%m%d_%H%M%S}")
ARCHIVE_NAME="${ARCHIVE_PREFIX:-backup}_${TIMESTAMP}${ARCHIVE_EXT:-.tar.gz}"
ARCHIVE_PATH="${DEST_DIR}/${ARCHIVE_NAME}"

# Optional delay via TEST_SLEEP env var to test concurrent lock collisions
sleep "${TEST_SLEEP:-0}"

if ! tar -czf "$ARCHIVE_PATH" -C "$(dirname "$SRC_DIR")" "$(basename "$SRC_DIR")" 2>/dev/null; then
    log_msg "ERROR: Failed to create archive '$ARCHIVE_PATH'."
    exit "${EXIT_ERR_ARCHIVE:-3}"
fi

chown "${BACKUP_USER:-$(whoami)}:${BACKUP_GROUP:-$(id -gn)}" "$ARCHIVE_PATH" 2>/dev/null || true
chmod "${ARCHIVE_MODE:-640}" "$ARCHIVE_PATH"

# [MEMBER 3] SHA-256 checksum generation
CHECKSUM=$(sha256sum "$ARCHIVE_PATH" | awk '{print $1}')
echo "$CHECKSUM  $ARCHIVE_NAME" > "${ARCHIVE_PATH}.sha256"

# [MEMBER 5] Generate summary report for Docker read-only inspection
cat << REPORT > "$REPORT_FILE"
==================================================
LAPORAN OTOMASI BACKUP & PEMULIHAN DATA (TOPIK 5A)
==================================================
Waktu Eksekusi   : $(date '+%Y-%m-%d %H:%M:%S')
Direktori Sumber : $SRC_DIR
Direktori Tujuan : $DEST_DIR
Nama Arsip       : $ARCHIVE_NAME
SHA256 Checksum  : $CHECKSUM
Status Backup    : BERHASIL (EXIT 0)
==================================================
REPORT

log_msg "SUCCESS: Archive '$ARCHIVE_NAME' created (SHA256: $CHECKSUM)"
exit 0
