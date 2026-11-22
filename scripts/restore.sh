#!/usr/bin/env bash
set -euo pipefail

if [ -f "config/backup.conf" ]; then
  source config/backup.conf
fi

if [ -f "scripts/verify.sh" ]; then
  source scripts/verify.sh
fi

EXIT_OK="${EXIT_OK:-0}"
EXIT_ERR_RESTORE="${EXIT_ERR_RESTORE:-5}"
RESTORE_DIR="${RESTORE_DIR:-$PWD/restore_test}"
LOG_FILE="${LOG_FILE:-logs/backup.log}"

mkdir -p "$(dirname "$LOG_FILE")"

log_msg() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Cek apakah user memasukkan nama file arsip
if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <archive_path> [target_dir]" >&2
  exit "$EXIT_ERR_RESTORE"
fi

ARCHIVE_PATH="$1"
TARGET_DIR="${2:-$RESTORE_DIR}"

# Cek apakah file arsipnya benar-benar ada
if [ ! -f "$ARCHIVE_PATH" ]; then
  log_msg "ERROR [RESTORE]: File arsip '$ARCHIVE_PATH' tidak ditemukan."
  exit "$EXIT_ERR_RESTORE"
fi

# Cek integritas arsip (kalau rusak, tolak sebelum diekstrak!)
if ! verify_checksum "$ARCHIVE_PATH"; then
  log_msg "ERROR [RESTORE]: Cek integritas gagal untuk '$ARCHIVE_PATH'. Restore ditolak!"
  exit "$EXIT_ERR_RESTORE"
fi

# Kalau lolos cek, baru bongkar/pulihkan datanya
mkdir -p "$TARGET_DIR"
if ! tar -xzf "$ARCHIVE_PATH" -C "$TARGET_DIR"; then
  log_msg "ERROR [RESTORE]: Gagal mengekstrak '$ARCHIVE_PATH' ke '$TARGET_DIR'."
  exit "$EXIT_ERR_RESTORE"
fi

log_msg "SUCCESS [RESTORE]: Data berhasil dipulihkan dari '$ARCHIVE_PATH' ke '$TARGET_DIR'."
exit "$EXIT_OK"
