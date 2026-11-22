#!/usr/bin/env bash
set -u

generate_checksum() {
  local archive_path="${1:-}"
  if [[ -z "$archive_path" || ! -f "$archive_path" ]]; then
    echo "[ERROR] Cannot generate checksum; archive missing: ${archive_path:-<empty>}" >&2
    return 2
  fi

  local dir_name base_name
  dir_name="$(cd "$(dirname "$archive_path")" && pwd)"
  base_name="$(basename "$archive_path")"

  (
    cd "$dir_name" || exit 2
    sha256sum "$base_name" > "${base_name}.sha256"
  )
}

verify_checksum() {
  local archive_path="${1:-}"
  local checksum_path="${2:-${archive_path}.sha256}"

  if [[ -z "$archive_path" || ! -f "$archive_path" ]]; then
    echo "[ERROR] Archive not found: ${archive_path:-<empty>}" >&2
    return 2
  fi

  if [[ ! -f "$checksum_path" ]]; then
    echo "[ERROR] Checksum file not found: $checksum_path" >&2
    return 2
  fi

  local archive_dir archive_file sum_dir sum_file
  archive_dir="$(cd "$(dirname "$archive_path")" && pwd)"
  archive_file="$(basename "$archive_path")"
  sum_dir="$(cd "$(dirname "$checksum_path")" && pwd)"
  sum_file="$(basename "$checksum_path")"

  local temp_copied=0
  if [[ "$archive_dir" != "$sum_dir" ]]; then
    cp "$archive_path" "$sum_dir/$archive_file" || return 2
    temp_copied=1
  fi

  local status=0
  if (cd "$sum_dir" && sha256sum -c --status "$sum_file"); then
    echo "[PASS] Checksum verified for $archive_path"
    status=0
  else
    echo "[FAIL] Checksum mismatch for $archive_path" >&2
    status=4
  fi

  if [[ "$temp_copied" -eq 1 ]]; then
    rm -f "$sum_dir/$archive_file"
  fi

  return "$status"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  verify_checksum "${1:-}" "${2:-}"
  exit $?
fi
