#!/bin/sh
# enhancements/lib/module_common.sh
# Shared POSIX-compliant helper library for reversible enhancement modules.
# Enforces snapshot-before-write, verified readback, and strict failure preservation
# (never uses fabricated default fallbacks or silent error suppression).

resolve_path() {
    if [ -n "${MOCK_ROOT:-}" ]; then
        printf '%s%s\n' "${MOCK_ROOT%/}" "$1"
    else
        printf '%s\n' "$1"
    fi
}

mc_read_raw() {
    _virt="$1"
    _real=$(resolve_path "$_virt")
    [ -f "$_real" ] && [ -r "$_real" ] || return 1
    _val=$(cat "$_real" 2>/dev/null) || return 1
    _val=$(printf '%s' "$_val" | tr -d ' \t\r\n')
    [ -n "$_val" ] || return 1
    printf '%s\n' "$_val"
}

mc_normalize_rps() {
    _raw="$1"
    if printf '%s' "$_raw" | grep -Eq '^0+$'; then
        printf '0\n'
    else
        printf '%s\n' "$_raw" | sed 's/^0*//'
    fi
}

mc_values_match() {
    _virt="$1"
    _exp="$2"
    _act="$3"
    [ -n "$_act" ] || return 1
    [ "$_act" = "$_exp" ] && return 0
    case "$_virt" in
        */rps_cpus)
            [ "$(mc_normalize_rps "$_act")" = "$(mc_normalize_rps "$_exp")" ] && return 0
            ;;
    esac
    return 1
}

mc_write_and_verify() {
    _virt="$1"
    _val="$2"
    _real=$(resolve_path "$_virt")
    [ -f "$_real" ] && [ -w "$_real" ] || return 1
    printf '%s\n' "$_val" > "$_real" 2>/dev/null || return 1
    _readback=$(mc_read_raw "$_virt") || return 1
    mc_values_match "$_virt" "$_val" "$_readback"
}

mc_state_file() {
    printf '%s/state/%s.state\n' "$1" "$2"
}

mc_manifest_trial_state() {
    _manifest="${1}/manifest.json"
    [ -f "$_manifest" ] || return 1
    sed -n 's/.*"trial_state":[ \t]*"\([^"]*\)".*/\1/p' "$_manifest" | head -n 1
}

mc_kv_inspect() {
    _mod="$1"
    _specs="$2"
    _ok=0
    echo "Inspecting ${_mod} targets:"
    for _entry in $_specs; do
        _req=$(printf '%s' "$_entry" | cut -d'|' -f1)
        _virt=$(printf '%s' "$_entry" | cut -d'|' -f2)
        _target=$(printf '%s' "$_entry" | cut -d'|' -f3)
        if _cur=$(mc_read_raw "$_virt"); then
            echo "  [OK] ${_virt} current=${_cur} trial=${_target} (${_req})"
        else
            if [ "$_req" = "req" ]; then
                echo "  [MISSING] ${_virt} required target missing or unreadable" >&2
                _ok=1
            else
                echo "  [ABSENT_OPT] ${_virt} optional node not present"
            fi
        fi
    done
    return "$_ok"
}

mc_kv_stage() {
    _mod="$1"
    _target_dir="$2"
    mkdir -p "${_target_dir}/state" "${_target_dir}/bin" || return 1
    return 0
}

mc_kv_rollback_entries() {
    _entries="$1"
    _failed=0
    # Reverse order line by line using tac/awk fallback for BusyBox compatibility
    _rev=$(printf '%s\n' "$_entries" | awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}')
    for _line in $_rev; do
        [ -n "$_line" ] || continue
        _virt=$(printf '%s' "$_line" | cut -d'|' -f1)
        _orig=$(printf '%s' "$_line" | cut -d'|' -f2)
        if ! mc_write_and_verify "$_virt" "$_orig"; then
            echo "ERROR: Failed to restore ${_virt} to '${_orig}'" >&2
            _failed=1
        fi
    done
    return "$_failed"
}

mc_kv_apply() {
    _mod="$1"
    _target_dir="$2"
    _specs="$3"
    _state_file=$(mc_state_file "$_target_dir" "$_mod")
    _tmp_state="${_state_file}.tmp.$$"

    mkdir -p "${_target_dir}/state" || return 1
    if [ -f "$_state_file" ]; then
        echo "ERROR: Existing active state snapshot $_state_file; rollback before re-applying." >&2
        return 1
    fi

    # Phase 1: Snapshot all existing targets BEFORE mutating anything
    : > "$_tmp_state" || return 1
    for _entry in $_specs; do
        _req=$(printf '%s' "$_entry" | cut -d'|' -f1)
        _virt=$(printf '%s' "$_entry" | cut -d'|' -f2)
        _trial=$(printf '%s' "$_entry" | cut -d'|' -f3)
        _real=$(resolve_path "$_virt")
        if [ -e "$_real" ]; then
            _orig=$(mc_read_raw "$_virt") || {
                rm -f "$_tmp_state" 2>/dev/null || true
                echo "ERROR: Snapshot failed reading $_virt" >&2
                return 1
            }
            printf '%s|%s|%s\n' "$_virt" "$_orig" "$_trial" >> "$_tmp_state" || {
                rm -f "$_tmp_state" 2>/dev/null || true
                return 1
            }
        elif [ "$_req" = "req" ]; then
            rm -f "$_tmp_state" 2>/dev/null || true
            echo "ERROR: Required target missing: $_virt" >&2
            return 1
        fi
    done

    mv "$_tmp_state" "$_state_file" || {
        rm -f "$_tmp_state" 2>/dev/null || true
        return 1
    }

    # Phase 2: Apply each target and roll back applied keys atomically on failure
    _applied=""
    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _virt=$(printf '%s' "$_line" | cut -d'|' -f1)
        _orig=$(printf '%s' "$_line" | cut -d'|' -f2)
        _trial=$(printf '%s' "$_line" | cut -d'|' -f3)
        if mc_write_and_verify "$_virt" "$_trial"; then
            _applied="${_applied}${_virt}|${_orig}
"
        else
            echo "ERROR: Write/readback verification failed for ${_virt}=${_trial}; reverting partial writes." >&2
            if mc_kv_rollback_entries "$_applied"; then
                rm -f "$_state_file" || return 1
            else
                echo "ERROR: Partial apply recovery failed; preserving ${_state_file}" >&2
            fi
            return 1
        fi
    done < "$_state_file"

    return 0
}

mc_kv_rollback() {
    _mod="$1"
    _target_dir="$2"
    _state_file=$(mc_state_file "$_target_dir" "$_mod")

    if [ ! -f "$_state_file" ]; then
        _tstate=$(mc_manifest_trial_state "$_target_dir" 2>/dev/null || echo "")
        if [ "$_tstate" = "staged" ] || [ "$_tstate" = "rolled_back" ]; then
            return 0
        fi
        echo "ERROR: Missing snapshot state file $_state_file; refusing unverified default rollback." >&2
        return 1
    fi

    _entries=""
    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _virt=$(printf '%s' "$_line" | cut -d'|' -f1)
        _orig=$(printf '%s' "$_line" | cut -d'|' -f2)
        if [ -z "$_virt" ] || [ -z "$_orig" ]; then
            echo "ERROR: Corrupt state record in $_state_file; preserving state file." >&2
            return 1
        fi
        _entries="${_entries}${_virt}|${_orig}
"
    done < "$_state_file"

    [ -n "$_entries" ] || {
        echo "ERROR: Empty snapshot state file $_state_file; refusing cleanup." >&2
        return 1
    }

    if ! mc_kv_rollback_entries "$_entries"; then
        echo "ERROR: One or more targets failed rollback verification; preserving $_state_file." >&2
        return 1
    fi

    rm -f "$_state_file" || return 1
    return 0
}

mc_kv_verify() {
    _mod="$1"
    _target_dir="$2"
    _specs="$3"
    _state_file=$(mc_state_file "$_target_dir" "$_mod")
    [ -f "$_state_file" ] || return 1

    while IFS= read -r _line; do
        [ -n "$_line" ] || continue
        _virt=$(printf '%s' "$_line" | cut -d'|' -f1)
        _trial=$(printf '%s' "$_line" | cut -d'|' -f3)
        _cur=$(mc_read_raw "$_virt") || return 1
        mc_values_match "$_virt" "$_trial" "$_cur" || return 1
    done < "$_state_file"
    return 0
}

mc_kv_status() {
    _mod="$1"
    _specs="$2"
    echo "  Module: ${_mod}"
    for _entry in $_specs; do
        _virt=$(printf '%s' "$_entry" | cut -d'|' -f2)
        _trial=$(printf '%s' "$_entry" | cut -d'|' -f3)
        _cur=$(mc_read_raw "$_virt" 2>/dev/null || echo "UNAVAILABLE")
        echo "    ${_virt}: ${_cur} (Trial Target: ${_trial})"
    done
}
