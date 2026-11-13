#!/bin/sh
# enhancements/installer.sh
# Reversible RA82 Enhancement Lifecycle Manager (Milestone M12.6 Blocker Closure P0-2)
# Separates stage / inspect / trial / rollback / uninstall and disables persistent
# boot installation (/data/enhancements, /data/auto_run.sh) for this release.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_MODULES_DIR="${SCRIPT_DIR}/modules"
SRC_LIB_DIR="${SCRIPT_DIR}/lib"
AVAILABLE_MODULES="module_rps module_napi module_sysctl module_wireguard"

resolve_path() {
    if [ -n "${MOCK_ROOT:-}" ]; then
        printf '%s%s\n' "${MOCK_ROOT%/}" "$1"
    else
        printf '%s\n' "$1"
    fi
}

log_info() { echo "[installer] INFO: $*"; }
log_ok()   { echo "[installer] PASS: $*"; }
log_warn() { echo "[installer] WARN: $*"; }
log_err()  { echo "[installer] ERROR: $*" >&2; }

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] <COMMAND>

Commands:
  list        List available enhancement modules (read-only)
  inspect     Inspect baseline sysfs/sysctl readiness (read-only; zero writes)
  stage       Stage module files & manifest to /tmp/enhancements (zero runtime writes)
  trial       Apply reversible runtime trial (requires --authorize-trial)
  rollback    Restore snapshotted baseline values and verify readbacks
  uninstall   Rollback active trial and purge staged /tmp/enhancements cleanly
  verify      Verify active trial state against module targets
  status      Show current enhancement manifest and runtime parameters

Options:
  --volatile              Target volatile RAM (/tmp/enhancements) [default]
  --persistent            DISABLED in release M12.6 (rejected cleanly)
  --confirm-persistent    DISABLED in release M12.6 (rejected cleanly)
  --authorize-trial       Required confirmation flag for 'trial'
  --modules <m1,m2,...>   Comma-separated subset (${AVAILABLE_MODULES})
  -h, --help              Show this help
EOF
}

MODE="volatile"
AUTHORIZE_TRIAL=0
SELECTED_MODULES="$AVAILABLE_MODULES"
ACTION=""

while [ $# -gt 0 ]; do
    case "$1" in
        --volatile) MODE="volatile" ;;
        --persistent|--confirm-persistent) MODE="persistent" ;;
        --authorize-trial) AUTHORIZE_TRIAL=1 ;;
        --modules)
            shift
            [ $# -gt 0 ] || { log_err "--modules requires an argument"; exit 1; }
            SELECTED_MODULES=$(printf '%s' "$1" | tr ',' ' ')
            ;;
        -h|--help) show_usage; exit 0 ;;
        list|inspect|stage|trial|rollback|uninstall|verify|status|install)
            ACTION="$1"
            ;;
        *)
            log_err "Unknown option or command: $1"
            show_usage >&2
            exit 1
            ;;
    esac
    shift
done

[ -n "$ACTION" ] || { show_usage; exit 1; }

if [ "$MODE" = "persistent" ]; then
    log_err "Persistent mode (/data/enhancements, /data/auto_run.sh) is DISABLED for release M12.6."
    log_err "Use volatile lifecycle instead: stage -> inspect -> trial --authorize-trial -> rollback -> uninstall."
    exit 1
fi

if [ "$ACTION" = "install" ]; then
    log_err "Direct 'install' is removed under P0-2 safety separation."
    log_err "Run 'stage' (copy files only), 'inspect' (read-only checks), or 'trial --authorize-trial' (reversible runtime trial)."
    exit 1
fi

TARGET_DIR=$(resolve_path "/tmp/enhancements")
AUTO_RUN_FILE=$(resolve_path "/data/auto_run.sh")
MANIFEST_FILE="${TARGET_DIR}/manifest.json"

validate_modules() {
    for _mod in $SELECTED_MODULES; do
        _valid=0
        for _avail in $AVAILABLE_MODULES; do
            [ "$_mod" = "$_avail" ] && _valid=1 && break
        done
        [ "$_valid" -eq 1 ] || {
            log_err "Unknown enhancement module: $_mod"
            return 1
        }
    done
    return 0
}

write_manifest() {
    _trial_state="$1"
    _mods_json=$(printf '%s' "$2" | awk '{for(i=1;i<=NF;i++) printf "\"%s\"%s", $i, (i<NF?", ":"")}')
    cat << EOF > "$MANIFEST_FILE"
{
  "installer_version": "m12.6-p0-2",
  "mode": "volatile",
  "trial_state": "${_trial_state}",
  "target_dir": "/tmp/enhancements",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date)",
  "modules": [${_mods_json}]
}
EOF
}

manifest_trial_state() {
    [ -f "$MANIFEST_FILE" ] || return 1
    sed -n 's/.*"trial_state":[ \t]*"\([^"]*\)".*/\1/p' "$MANIFEST_FILE" | head -n 1
}

manifest_modules() {
    [ -f "$MANIFEST_FILE" ] || return 1
    sed -n 's/.*"modules":[ \t]*\[\(.*\)\].*/\1/p' "$MANIFEST_FILE" | tr -d '"' | tr ',' ' '
}

strip_autorun_hook_only() {
    [ -f "$AUTO_RUN_FILE" ] || return 0
    if grep -q "BEGIN RA82 ENHANCEMENTS HOOK" "$AUTO_RUN_FILE" 2>/dev/null; then
        _tmp_auto="${AUTO_RUN_FILE}.tmp.$$"
        awk '
            /# BEGIN RA82 ENHANCEMENTS HOOK/ { skip=1; next }
            /# END RA82 ENHANCEMENTS HOOK/ { skip=0; next }
            !skip { print }
        ' "$AUTO_RUN_FILE" > "$_tmp_auto" || {
            rm -f "$_tmp_auto" 2>/dev/null || true
            return 1
        }
        mv "$_tmp_auto" "$AUTO_RUN_FILE" || return 1
        log_info "Removed RA82 hook marker block while preserving existing /data/auto_run.sh contents."
    fi
    return 0
}

cmd_list() {
    echo "Available RA82 Enhancement Modules (Volatile RAM Trial Only):"
    for _mod in $AVAILABLE_MODULES; do
        _desc=$(sh "${SRC_MODULES_DIR}/${_mod}.sh" describe 2>/dev/null || echo "")
        printf '  %-18s %s\n' "$_mod" "$_desc"
    done
    return 0
}

cmd_inspect() {
    validate_modules || return 1
    _rc=0
    for _mod in $SELECTED_MODULES; do
        sh "${SRC_MODULES_DIR}/${_mod}.sh" inspect || _rc=1
    done
    return "$_rc"
}

cmd_stage() {
    validate_modules || return 1
    if [ -f "$MANIFEST_FILE" ]; then
        _cur_state=$(manifest_trial_state 2>/dev/null || echo "")
        if [ "$_cur_state" = "trial_active" ] || [ "$_cur_state" = "rollback_incomplete" ]; then
            log_err "Cannot restage while trial_state is '${_cur_state}'; run rollback first."
            return 1
        fi
    fi

    mkdir -p "${TARGET_DIR}/modules" "${TARGET_DIR}/lib" "${TARGET_DIR}/state" "${TARGET_DIR}/bin" || return 1
    cp -f "${SRC_LIB_DIR}/module_common.sh" "${TARGET_DIR}/lib/module_common.sh" || return 1
    chmod 644 "${TARGET_DIR}/lib/module_common.sh" || return 1

    for _mod in $SELECTED_MODULES; do
        _src="${SRC_MODULES_DIR}/${_mod}.sh"
        _dst="${TARGET_DIR}/modules/${_mod}.sh"
        [ -f "$_src" ] || { log_err "Module source missing: $_src"; return 1; }
        cp -f "$_src" "$_dst" || return 1
        chmod +x "$_dst" || return 1
        sh "$_dst" stage "$TARGET_DIR" || return 1
    done

    write_manifest "staged" "$SELECTED_MODULES" || return 1
    log_ok "Staged modules cleanly into ${TARGET_DIR} (zero runtime changes performed)."
    return 0
}

rollback_module_list() {
    _mods="$1"
    _rev=$(printf '%s\n' $_mods | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}')
    _failed=0
    for _mod in $_rev; do
        [ -n "$_mod" ] || continue
        _mod_path="${TARGET_DIR}/modules/${_mod}.sh"
        if [ ! -f "$_mod_path" ]; then
            log_err "Missing staged module during rollback: ${_mod_path}"
            _failed=1
            continue
        fi
        if ! sh "$_mod_path" rollback "$TARGET_DIR"; then
            log_err "Module ${_mod} rollback failed!"
            _failed=1
        else
            log_ok "Module ${_mod} rolled back and verified."
        fi
    done
    return "$_failed"
}

cmd_trial() {
    [ "$AUTHORIZE_TRIAL" -eq 1 ] || {
        log_err "Trial requires explicit '--authorize-trial' flag."
        return 1
    }
    validate_modules || return 1

    if [ ! -f "$MANIFEST_FILE" ]; then
        cmd_stage || return 1
    else
        _cur_state=$(manifest_trial_state 2>/dev/null || echo "")
        if [ "$_cur_state" = "staged" ] || [ "$_cur_state" = "rolled_back" ]; then
            cmd_stage || return 1
        else
            log_err "Cannot start trial from state '${_cur_state}'; run rollback first."
            return 1
        fi
    fi

    write_manifest "trial_active" "$SELECTED_MODULES" || return 1

    _applied=""
    for _mod in $SELECTED_MODULES; do
        log_info "Applying reversible trial module: ${_mod}..."
        if sh "${TARGET_DIR}/modules/${_mod}.sh" apply "$TARGET_DIR"; then
            _applied="${_applied} ${_mod}"
        else
            log_err "Trial apply failed on ${_mod}; rolling back prior modules..."
            if rollback_module_list "$_applied"; then
                write_manifest "rolled_back" "$SELECTED_MODULES" || true
            else
                write_manifest "rollback_incomplete" "$SELECTED_MODULES" || true
            fi
            return 1
        fi
    done

    log_ok "Volatile trial active across: ${SELECTED_MODULES}"
    return 0
}

cmd_rollback() {
    [ -d "$TARGET_DIR" ] && [ -f "$MANIFEST_FILE" ] || {
        log_err "No enhancement manifest found at $MANIFEST_FILE; refusing unverified rollback."
        return 1
    }
    _mods=$(manifest_modules)
    [ -n "$_mods" ] || _mods="$SELECTED_MODULES"

    if rollback_module_list "$_mods"; then
        write_manifest "rolled_back" "$_mods" || return 1
        log_ok "All enhancement modules rolled back cleanly."
        return 0
    else
        write_manifest "rollback_incomplete" "$_mods" || true
        log_err "Rollback incomplete; preserving ${TARGET_DIR} and state snapshots."
        return 1
    fi
}

cmd_uninstall() {
    if [ -d "$TARGET_DIR" ]; then
        _tstate=$(manifest_trial_state 2>/dev/null || echo "")
        _has_state=0
        for _sf in "${TARGET_DIR}/state/"*.state; do
            [ -e "$_sf" ] && _has_state=1 && break
        done

        if [ "$_has_state" -eq 1 ] || [ "$_tstate" = "trial_active" ] || [ "$_tstate" = "rollback_incomplete" ]; then
            if ! cmd_rollback; then
                log_err "Refusing to purge ${TARGET_DIR} because rollback failed or is incomplete!"
                return 1
            fi
        fi

        rm -rf "$TARGET_DIR" || {
            log_err "Failed to remove ${TARGET_DIR}"
            return 1
        }
    fi

    strip_autorun_hook_only || return 1
    log_ok "Uninstall completed cleanly."
    return 0
}

cmd_verify() {
    [ -f "$MANIFEST_FILE" ] || { log_err "Not staged/active: $MANIFEST_FILE missing"; return 1; }
    _tstate=$(manifest_trial_state 2>/dev/null || echo "")
    [ "$_tstate" = "trial_active" ] || {
        log_err "Expected trial_state=trial_active, got '${_tstate}'"
        return 1
    }
    _mods=$(manifest_modules)
    for _mod in $_mods; do
        if ! sh "${TARGET_DIR}/modules/${_mod}.sh" verify "$TARGET_DIR"; then
            log_err "Module ${_mod} verification failed!"
            return 1
        fi
    done
    log_ok "All active enhancement modules verified."
    return 0
}

cmd_status() {
    echo "========================================================================"
    echo "RA82 ENHANCEMENT SYSTEM STATUS (P0-2 Separated Lifecycle)"
    echo "========================================================================"
    if [ -f "$MANIFEST_FILE" ]; then
        echo "  Manifest: ${MANIFEST_FILE}"
        echo "  State:    $(manifest_trial_state 2>/dev/null || echo unknown)"
        echo "  Modules:  $(manifest_modules 2>/dev/null || echo unknown)"
        for _mod in $(manifest_modules 2>/dev/null); do
            sh "${TARGET_DIR}/modules/${_mod}.sh" status "$TARGET_DIR"
        done
    else
        echo "  Not staged at ${TARGET_DIR}. Inspecting source modules:"
        for _mod in $AVAILABLE_MODULES; do
            sh "${SRC_MODULES_DIR}/${_mod}.sh" status "$TARGET_DIR"
        done
    fi
    return 0
}

case "$ACTION" in
    list) cmd_list ;;
    inspect) cmd_inspect ;;
    stage) cmd_stage ;;
    trial) cmd_trial ;;
    rollback) cmd_rollback ;;
    uninstall) cmd_uninstall ;;
    verify) cmd_verify ;;
    status) cmd_status ;;
esac
