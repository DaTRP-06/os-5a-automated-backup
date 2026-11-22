#!/usr/bin/env bash
# ==============================================================================
# Project 5A: Sistem Otomasi Backup dan Pemulihan Data Linux
# Script : scripts/validate.sh
# Owner  : Member 1 (Validasi Sumber dan Parameter)
# Purpose: Validate CLI parameters, source directory existence/readability/
#          non-emptiness, and basic destination path sanity before archiving.
# Exit Codes:
#   0 (EXIT_OK)         - Valid non-empty source and valid parameters
#   2 (EXIT_ERR_SOURCE) - Invalid parameters, missing/unreadable/empty source,
#                         or invalid destination path type
# ==============================================================================

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_CONFIG="${REPO_ROOT}/config/backup.conf"
COMMON_LIB="${SCRIPT_DIR}/lib/common.sh"

# Default exit codes (overridden once config/backup.conf is loaded)
EXIT_OK=0
EXIT_ERR_SOURCE=2

CONFIG_FILE="${DEFAULT_CONFIG}"
CLI_SOURCE=""
CLI_DEST=""

# ------------------------------------------------------------------------------
# Usage / Help
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Validate backup source directory and parameters.

Options:
  -s, --source <dir>   Source directory to back up (overrides SOURCE_DIR in config)
  -d, --dest <dir>     Destination backup directory (overrides BACKUP_DIR in config)
  -c, --config <file>  Path to backup configuration file (default: config/backup.conf)
  -h, --help           Show this help message and exit

Exit codes:
  0  Validation succeeded
  2  Validation failed (invalid argument, missing/unreadable/empty source, etc.)
EOF
}

# ------------------------------------------------------------------------------
# Fallback Logging Helpers (used if scripts/lib/common.sh is not yet present)
# ------------------------------------------------------------------------------
_write_log() {
    local level="$1"
    local message="$2"
    local timestamp user_name line

    timestamp="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')"
    user_name="$(whoami 2>/dev/null || echo 'unknown')"
    line="[${timestamp}] [${level}] [PID:$$] [USER:${user_name}] [${SCRIPT_NAME}] ${message}"

    if [[ "${level}" == "ERROR" || "${level}" == "WARN" ]]; then
        printf '%s\n' "${line}" >&2
    else
        printf '%s\n' "${line}"
    fi

    # Append to LOG_FILE only if configured and writable (never break exit status)
    if [[ -n "${LOG_FILE:-}" ]]; then
        local log_parent
        log_parent="$(dirname "${LOG_FILE}")"
        if [[ -d "${log_parent}" && -w "${log_parent}" ]] && { [[ ! -e "${LOG_FILE}" ]] || [[ -w "${LOG_FILE}" ]]; }; then
            printf '%s\n' "${line}" >> "${LOG_FILE}" 2>/dev/null || true
        fi
    fi
}

log_info()  { _write_log "INFO"  "$1"; }
log_warn()  { _write_log "WARN"  "$1"; }
log_error() { _write_log "ERROR" "$1"; }

# ------------------------------------------------------------------------------
# Parse CLI Arguments
# ------------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--source)
                if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                    log_error "Option '$1' requires a valid directory path argument."
                    exit "${EXIT_ERR_SOURCE}"
                fi
                CLI_SOURCE="$2"
                shift 2
                ;;
            -d|--dest)
                if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                    log_error "Option '$1' requires a valid directory path argument."
                    exit "${EXIT_ERR_SOURCE}"
                fi
                CLI_DEST="$2"
                shift 2
                ;;
            -c|--config)
                if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                    log_error "Option '$1' requires a configuration file path."
                    exit "${EXIT_ERR_SOURCE}"
                fi
                CONFIG_FILE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit "${EXIT_OK}"
                ;;
            *)
                log_error "Unknown or unexpected argument: '$1'. Run '${SCRIPT_NAME} --help' for usage."
                exit "${EXIT_ERR_SOURCE}"
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Load Configuration & Optional Shared Library
# ------------------------------------------------------------------------------
load_environment() {
    if [[ ! -f "${CONFIG_FILE}" || ! -r "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found or unreadable: '${CONFIG_FILE}'"
        exit "${EXIT_ERR_SOURCE}"
    fi

    # shellcheck source=../config/backup.conf
    source "${CONFIG_FILE}"

    # Load Member 5's shared logging library if available
    if [[ -f "${COMMON_LIB}" && -r "${COMMON_LIB}" ]]; then
        # shellcheck source=./lib/common.sh
        source "${COMMON_LIB}"
    fi

    # Apply CLI overrides after loading defaults from backup.conf
    if [[ -n "${CLI_SOURCE}" ]]; then
        SOURCE_DIR="${CLI_SOURCE}"
    fi
    if [[ -n "${CLI_DEST}" ]]; then
        BACKUP_DIR="${CLI_DEST}"
    fi
}

# ------------------------------------------------------------------------------
# Path Normalization Helper
# ------------------------------------------------------------------------------
normalize_path() {
    local target="$1"
    if command -v realpath >/dev/null 2>&1 && [[ -e "${target}" ]]; then
        realpath "${target}" 2>/dev/null || printf '%s' "${target%/}"
    else
        if [[ "${target}" == "/" ]]; then
            printf '/'
        else
            printf '%s' "${target%/}"
        fi
    fi
}

# ------------------------------------------------------------------------------
# Validation Logic
# ------------------------------------------------------------------------------
validate_inputs() {
    local src="${SOURCE_DIR:-}"
    local dst="${BACKUP_DIR:-}"

    # 1. Check required parameters are not empty
    if [[ -z "${src}" ]]; then
        log_error "Source directory parameter (SOURCE_DIR / --source) is empty."
        return "${EXIT_ERR_SOURCE}"
    fi

    if [[ -z "${dst}" ]]; then
        log_error "Destination directory parameter (BACKUP_DIR / --dest) is empty."
        return "${EXIT_ERR_SOURCE}"
    fi

    # 2. Check source existence, type, and access permissions
    if [[ ! -e "${src}" ]]; then
        log_error "Source directory does not exist: '${src}'"
        return "${EXIT_ERR_SOURCE}"
    fi

    if [[ ! -d "${src}" ]]; then
        log_error "Source path is not a directory: '${src}'"
        return "${EXIT_ERR_SOURCE}"
    fi

    if [[ ! -r "${src}" || ! -x "${src}" ]]; then
        log_error "Source directory is not readable/accessible by user '$(whoami)': '${src}'"
        return "${EXIT_ERR_SOURCE}"
    fi

    # 3. Validate destination path type & prevent recursive self-backup
    # Note: Destination writeability (-w) is validated by Member 2 (archive.sh, exit 3).
    if [[ -e "${dst}" && ! -d "${dst}" ]]; then
        log_error "Destination path exists but is not a directory: '${dst}'"
        return "${EXIT_ERR_SOURCE}"
    fi

    local norm_src norm_dst
    norm_src="$(normalize_path "${src}")"
    norm_dst="$(normalize_path "${dst}")"

    if [[ "${norm_src}" == "${norm_dst}" ]]; then
        log_error "Source and destination directories cannot be identical: '${norm_src}'"
        return "${EXIT_ERR_SOURCE}"
    fi

    # 4. Iterate entries in source directory to ensure non-empty & readable content
    local entry_count=0
    local unreadable_count=0
    local entry

    shopt -s nullglob dotglob
    for entry in "${src}"/*; do
        entry_count=$((entry_count + 1))
        if [[ ! -r "${entry}" ]]; then
            log_warn "Unreadable entry inside source directory: '${entry}'"
            unreadable_count=$((unreadable_count + 1))
        fi
    done
    shopt -u nullglob dotglob

    if [[ "${entry_count}" -eq 0 ]]; then
        log_error "Source directory is empty (0 entries found): '${src}'"
        return "${EXIT_ERR_SOURCE}"
    fi

    if [[ "${unreadable_count}" -gt 0 ]]; then
        log_error "Source directory contains ${unreadable_count} unreadable item(s): '${src}'"
        return "${EXIT_ERR_SOURCE}"
    fi

    log_info "Validation passed: source='${src}' (${entry_count} item(s)), dest='${dst}'"
    return "${EXIT_OK}"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    parse_args "$@"
    load_environment
    validate_inputs
    exit $?
}

main "$@"
