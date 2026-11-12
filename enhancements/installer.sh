#!/bin/sh
# enhancements/installer.sh
# ==============================================================================
# Modular RA82 Enhancement System Installer & Lifecycle Manager
# Workstream B, D, & F: Modern Userspace & Automated Optimization System
# Target: Xiaomi CR8808 / RA82 (Qualcomm IPQ5018 Dual-Core Cortex-A53)
#
# MODES:
#   Mode 1: --volatile
#     Deploys to /tmp/enhancements/ (100% RAM tmpfs, zero flash writes, cleans on reboot).
#   Mode 2: --persistent
#     Installs to /data/enhancements/ with /data/auto_run.sh hook.
#     STRICT SAFETY GUARD: Requires explicit '--confirm-persistent' confirmation flag!
#
# MODULES:
#   module_rps, module_napi, module_sysctl, module_wireguard
#
# UNINSTALLATION:
#   enhancements/installer.sh --uninstall [--volatile | --persistent]
# ==============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"

MOCK_ROOT="${MOCK_ROOT:-}"

MODE=""
CONFIRM_PERSISTENT=0
SELECTED_MODULES=""
COMMAND="install"

log_info() { echo "[ENHANCE-INFO]  $*"; }
log_warn() { echo "[ENHANCE-WARN]  $*" >&2; }
log_err()  { echo "[ENHANCE-ERROR] $*" >&2; }
log_ok()   { echo "[ENHANCE-OK]    $*"; }

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --volatile)
            if [ "$MODE" = "persistent" ]; then
                log_err "--volatile and --persistent are mutually exclusive!"
                exit 1
            fi
            MODE="volatile"
            shift
            ;;
        --persistent)
            if [ "$MODE" = "volatile" ]; then
                log_err "--volatile and --persistent are mutually exclusive!"
                exit 1
            fi
            MODE="persistent"
            shift
            ;;
        --confirm-persistent)
            CONFIRM_PERSISTENT=1
            shift
            ;;
        --modules)
            SELECTED_MODULES="$2"
            shift 2
            ;;
        --module)
            if [ -z "$SELECTED_MODULES" ]; then
                SELECTED_MODULES="$2"
            else
                SELECTED_MODULES="${SELECTED_MODULES},$2"
            fi
            shift 2
            ;;
        --uninstall|uninstall)
            COMMAND="uninstall"
            shift
            ;;
        install|status|verify|list)
            COMMAND="$1"
            shift
            ;;
        --help|-h)
            cat << 'HELP_EOF'
Usage: enhancements/installer.sh [options] [command]

Commands:
  install                 Install selected enhancement modules (default)
  uninstall               Rollback and completely remove installed enhancements
  status                  Check status of installed modules
  verify                  Verify active kernel/userspace parameters
  list                    List available enhancement modules

Options:
  --volatile              Deploy to /tmp/enhancements (100% RAM, zero flash risk) [Default]
  --persistent            Install to /data/enhancements (persists across reboots)
  --confirm-persistent    Mandatory confirmation flag required when using --persistent
  --modules <mod1,mod2>   Comma-separated list of modules to install
  --module <mod>          Single module name to install

Available Modules:
  module_rps              Receive Packet Steering (eth0 softirqs to CPU1)
  module_napi             NAPI network backlog (16384) & budget (600)
  module_sysctl           TCP FastOpen (TFO 3), tw_reuse, 30s TIME_WAIT, conntrack
  module_wireguard        Isolated wg1 testbed configuration (zero-touch on wg0)
HELP_EOF
            exit 0
            ;;
        *)
            log_err "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Default mode
if [ -z "$MODE" ]; then
    MODE="volatile"
fi

# Resolve target directory based on mode
if [ "$MODE" = "persistent" ]; then
    TARGET_DIR="${MOCK_ROOT}/data/enhancements"
    AUTO_RUN_FILE="${MOCK_ROOT}/data/auto_run.sh"
else
    TARGET_DIR="${MOCK_ROOT}/tmp/enhancements"
    AUTO_RUN_FILE=""
fi

# Default modules if none specified
if [ -z "$SELECTED_MODULES" ]; then
    SELECTED_MODULES="module_rps,module_napi,module_sysctl,module_wireguard"
fi

# ------------------------------------------------------------------------------
# HOOK MANAGEMENT FOR /data/auto_run.sh
# ------------------------------------------------------------------------------
install_autorun_hook() {
    _auto_file="$AUTO_RUN_FILE"
    if [ -z "$_auto_file" ]; then return 0; fi

    mkdir -p "$(dirname "$_auto_file")" 2>/dev/null || true
    if [ ! -f "$_auto_file" ]; then
        cat << 'EOF' > "$_auto_file"
#!/bin/sh
# /data/auto_run.sh - Xiaomi Router userspace initialization script
EOF
        chmod +x "$_auto_file" 2>/dev/null || true
    fi

    # Check if hook already present
    if grep -q "BEGIN RA82 ENHANCEMENTS HOOK" "$_auto_file" 2>/dev/null; then
        return 0
    fi

    cat << 'HOOK_EOF' >> "$_auto_file"

# --- BEGIN RA82 ENHANCEMENTS HOOK ---
if [ ! -f /data/SAFE_MODE ] && [ -x /data/enhancements/bin/auto_enhancements.sh ]; then
    /data/enhancements/bin/auto_enhancements.sh start >/dev/null 2>&1 &
fi
# --- END RA82 ENHANCEMENTS HOOK ---
HOOK_EOF
    chmod +x "$_auto_file" 2>/dev/null || true
    log_ok "Persistent startup hook installed into $_auto_file (SAFE_MODE protected)."
}

remove_autorun_hook() {
    _auto_file="$AUTO_RUN_FILE"
    if [ -z "$_auto_file" ] || [ ! -f "$_auto_file" ]; then return 0; fi

    # Safely strip hook block
    _tmp_auto="${_auto_file}.tmp.$$"
    awk '
        /# --- BEGIN RA82 ENHANCEMENTS HOOK ---/ { skip=1; next }
        /# --- END RA82 ENHANCEMENTS HOOK ---/ { skip=0; next }
        !skip { print }
    ' "$_auto_file" > "$_tmp_auto" 2>/dev/null || true

    if [ -f "$_tmp_auto" ]; then
        mv "$_tmp_auto" "$_auto_file"
        chmod +x "$_auto_file" 2>/dev/null || true
        log_ok "Removed persistent startup hook from $_auto_file."
    fi

    # If auto_run.sh only has the header or is empty, clean it up
    _non_comment=$(grep -v "^#" "$_auto_file" 2>/dev/null | tr -d ' \t\r\n' || echo "")
    if [ -z "$_non_comment" ]; then
        rm -f "$_auto_file" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# COMMAND: INSTALL
# ------------------------------------------------------------------------------
cmd_install() {
    log_info "================================================================================"
    log_info "INSTALLING RA82 ENHANCEMENTS"
    log_info "Mode:       ${MODE} ($( [ "$MODE" = "volatile" ] && echo "100% RAM /tmp, zero flash writes" || echo "Persistent /data" ))"
    log_info "Target Dir: ${TARGET_DIR}"
    log_info "Modules:    ${SELECTED_MODULES}"
    log_info "================================================================================"

    # Safety gate for persistent mode
    if [ "$MODE" = "persistent" ]; then
        if [ "$CONFIRM_PERSISTENT" -ne 1 ]; then
            log_err "CRITICAL SAFETY GATE: --persistent mode modifies /data partition."
            log_err "To execute persistent installation, you MUST supply '--confirm-persistent'."
            exit 1
        fi
        log_warn "Persistent mode confirmed with --confirm-persistent flag."
    fi

    mkdir -p "${TARGET_DIR}/bin" "${TARGET_DIR}/state" "${TARGET_DIR}/modules" 2>/dev/null || true

    # Deploy master runner auto_enhancements.sh
    cat << 'RUNNER_EOF' > "${TARGET_DIR}/bin/auto_enhancements.sh"
#!/bin/sh
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACTION="${1:-start}"

case "$ACTION" in
    start)
        for _f in "${BASE_DIR}/bin/"*_apply.sh; do
            if [ -x "$_f" ]; then "$_f" >/dev/null 2>&1 || true; fi
        done
        ;;
    stop)
        for _f in "${BASE_DIR}/bin/"*_rollback.sh; do
            if [ -x "$_f" ]; then "$_f" >/dev/null 2>&1 || true; fi
        done
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
        ;;
esac
RUNNER_EOF
    chmod +x "${TARGET_DIR}/bin/auto_enhancements.sh" 2>/dev/null || true

    # Install selected modules
    _installed_list=""
    _old_ifs="$IFS"
    IFS=','
    for _mod in $SELECTED_MODULES; do
        IFS="$_old_ifs"
        _mod_script="${MODULES_DIR}/${_mod}.sh"
        if [ ! -f "$_mod_script" ]; then
            log_err "Module not found: ${_mod} (${_mod_script})"
            exit 1
        fi

        log_info "Applying module: ${_mod}..."
        cp -f "$_mod_script" "${TARGET_DIR}/modules/${_mod}.sh"
        chmod +x "${TARGET_DIR}/modules/${_mod}.sh" 2>/dev/null || true

        if "${TARGET_DIR}/modules/${_mod}.sh" apply "$TARGET_DIR"; then
            log_ok "Module ${_mod} applied successfully."
            if [ -z "$_installed_list" ]; then
                _installed_list="\"${_mod}\""
            else
                _installed_list="${_installed_list}, \"${_mod}\""
            fi
        else
            log_err "Failed to apply module: ${_mod}"
            exit 1
        fi
    done
    IFS="$_old_ifs"

    # Write manifest file
    cat << EOF > "${TARGET_DIR}/manifest.json"
{
  "mode": "${MODE}",
  "installed_at": $(date +%s),
  "target_dir": "${TARGET_DIR}",
  "modules": [ ${_installed_list} ]
}
EOF

    # If persistent mode, install autorun hook
    if [ "$MODE" = "persistent" ]; then
        install_autorun_hook
    fi

    log_info "================================================================================"
    log_ok "RA82 ENHANCEMENTS SUCCESSFULLY INSTALLED IN ${MODE} MODE"
    log_info "================================================================================"
    exit 0
}

# ------------------------------------------------------------------------------
# COMMAND: UNINSTALL
# ------------------------------------------------------------------------------
cmd_uninstall() {
    log_info "================================================================================"
    log_info "UNINSTALLING RA82 ENHANCEMENTS"
    log_info "Target: ${TARGET_DIR}"
    log_info "================================================================================"

    if [ ! -d "$TARGET_DIR" ]; then
        # Check alternative mode if default target not found
        if [ "$MODE" = "volatile" ] && [ -d "${MOCK_ROOT}/data/enhancements" ]; then
            TARGET_DIR="${MOCK_ROOT}/data/enhancements"
            AUTO_RUN_FILE="${MOCK_ROOT}/data/auto_run.sh"
            MODE="persistent"
        elif [ "$MODE" = "persistent" ] && [ -d "${MOCK_ROOT}/tmp/enhancements" ]; then
            TARGET_DIR="${MOCK_ROOT}/tmp/enhancements"
            AUTO_RUN_FILE=""
            MODE="volatile"
        else
            log_info "No active enhancements found at ${TARGET_DIR}. Nothing to uninstall."
            exit 0
        fi
    fi

    # Roll back each module installed
    for _mod_file in "${TARGET_DIR}/modules/"*.sh; do
        if [ -x "$_mod_file" ]; then
            _mod_name=$(basename "$_mod_file" .sh)
            log_info "Rolling back module: ${_mod_name}..."
            "$_mod_file" rollback "$TARGET_DIR" || true
            log_ok "Module ${_mod_name} rolled back."
        fi
    done

    # Remove persistent autorun hook if applicable
    if [ "$MODE" = "persistent" ] || [ -f "${MOCK_ROOT}/data/auto_run.sh" ]; then
        remove_autorun_hook
    fi

    # Purge installation directory
    rm -rf "$TARGET_DIR" 2>/dev/null || true
    log_ok "Enhancement directory ${TARGET_DIR} completely purged."

    log_info "================================================================================"
    log_ok "UNINSTALLATION COMPLETE: SYSTEM RESTORED TO BASELINE"
    log_info "================================================================================"
    exit 0
}

# ------------------------------------------------------------------------------
# COMMAND: STATUS
# ------------------------------------------------------------------------------
cmd_status() {
    echo "================================================================================"
    echo "RA82 ENHANCEMENT SYSTEM STATUS"
    echo "================================================================================"
    if [ -f "${TARGET_DIR}/manifest.json" ]; then
        echo "Status:     INSTALLED (${MODE})"
        echo "Directory:  ${TARGET_DIR}"
        echo "Manifest:"
        cat "${TARGET_DIR}/manifest.json" | sed 's/^/  /'
        echo ""
        echo "Module Telemetry:"
        for _m in "${TARGET_DIR}/modules/"*.sh; do
            if [ -x "$_m" ]; then
                "$_m" status "$TARGET_DIR"
            fi
        done
    else
        echo "Status:     NOT INSTALLED at ${TARGET_DIR}"
    fi
    exit 0
}

# ------------------------------------------------------------------------------
# COMMAND: VERIFY
# ------------------------------------------------------------------------------
cmd_verify() {
    log_info "Verifying installed enhancement modules at ${TARGET_DIR}..."
    if [ ! -d "$TARGET_DIR" ]; then
        log_err "Enhancement directory not found: ${TARGET_DIR}"
        exit 1
    fi

    _all_ok=1
    for _m in "${TARGET_DIR}/modules/"*.sh; do
        if [ -x "$_m" ]; then
            _name=$(basename "$_m" .sh)
            if "$_m" verify "$TARGET_DIR"; then
                log_ok "Module ${_name}: VERIFIED"
            else
                log_err "Module ${_name}: VERIFICATION FAILED"
                _all_ok=0
            fi
        fi
    done

    if [ "$_all_ok" -eq 1 ]; then
        log_ok "All active enhancement modules verified successfully."
        exit 0
    else
        log_err "One or more modules failed verification!"
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# COMMAND: LIST
# ------------------------------------------------------------------------------
cmd_list() {
    echo "================================================================================"
    echo "AVAILABLE RA82 ENHANCEMENT MODULES"
    echo "================================================================================"
    for _m in "${MODULES_DIR}/"module_*.sh; do
        if [ -f "$_m" ]; then
            _b=$(basename "$_m" .sh)
            echo "Module: $_b"
            sh "$_m" describe | sed 's/^/  /'
            echo ""
        fi
    done
    exit 0
}

# Dispatch command
case "$COMMAND" in
    install)   cmd_install ;;
    uninstall) cmd_uninstall ;;
    status)    cmd_status ;;
    verify)    cmd_verify ;;
    list)      cmd_list ;;
    *) log_err "Unknown command: $COMMAND"; exit 1 ;;
esac
