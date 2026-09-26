#!/bin/bash
# Bash 3.2 compatible. Planning functions have no filesystem/process side effects.
set -euo pipefail

usage() {
    echo 'Usage: deploy.sh <candidate.app> [--enable-autostart] [--plan-only --state loaded=0|1,disabled=0|1,running=0|1 [--fail-at place|health]]' >&2
    exit 2
}

valid_state() {
    [[ $1 =~ ^loaded=[01],disabled=[01],running=[01]$ ]]
}

# The only definition of "restore to a state", shared by success and recovery.
plan_restore_state() {
    local state=$1 loaded disabled running
    loaded=${state:7:1}; disabled=${state:18:1}; running=${state:28:1}
    if [[ $loaded == 1 ]]; then
        printf '%s\n' ENABLE BOOTSTRAP HEALTH_CHECK
    elif [[ $running == 1 ]]; then
        printf '%s\n' OPEN HEALTH_CHECK
    fi
    if [[ $disabled == 1 ]]; then echo DISABLE; else echo ENABLE; fi
    if [[ $running == 0 ]]; then echo QUIT_APP; fi
    printf 'VERIFY_STATE %s\n' "$state"
}

# actual_loaded must come from a fresh CHECK_LOADED, never from the saved state.
plan_recovery() {
    local original=$1 actual_loaded=$2
    if [[ $actual_loaded == 1 ]]; then echo BOOTOUT; fi
    printf '%s\n' KILL_LEFTOVER REMOVE_NEW RESTORE_PREV
    plan_restore_state "$original"
}

# Pure function: original state, success target, simulated failure point.
# A failed action is printed once; all following actions belong to recovery.
plan_deployment() {
    local original=$1 target=$2 failure=$3 action restore
    printf '%s\n' VERIFY_CANDIDATE RECORD_STATE ARM_RECOVERY MOVE_ASIDE
    if [[ ${original:7:1} == 1 ]]; then echo BOOTOUT; fi
    printf '%s\n' KILL_LEFTOVER PLACE_CANDIDATE
    if [[ $failure == place ]]; then
        echo CHECK_LOADED
        plan_recovery "$original" 0
        return
    fi
    restore=$(plan_restore_state "$target")
    while IFS= read -r action; do
        printf '%s\n' "$action"
        if [[ $action == HEALTH_CHECK && $failure == health ]]; then
            echo CHECK_LOADED
            plan_recovery "$original" "${target:7:1}"
            return
        fi
    done <<< "$restore"
    # Neither bootstrap nor open ran: test the new bundle temporarily, even disabled.
    if [[ ${target:7:1} == 0 && ${target:28:1} == 0 ]]; then
        printf '%s\n' OPEN HEALTH_CHECK
        if [[ $failure == health ]]; then
            echo CHECK_LOADED
            plan_recovery "$original" 0
            return
        fi
        echo QUIT_APP
        printf 'VERIFY_STATE %s\n' "$target"
    fi
    printf '%s\n' DISARM_RECOVERY DELETE_PREV
}

candidate= plan_only=0 enable_autostart=0 supplied_state= failure=none
while [[ $# -gt 0 ]]; do
    case $1 in
        --enable-autostart) enable_autostart=1; shift ;;
        --plan-only) plan_only=1; shift ;;
        --state) [[ $# -ge 2 ]] || usage; supplied_state=$2; shift 2 ;;
        --fail-at) [[ $# -ge 2 ]] || usage; failure=$2; shift 2 ;;
        -*) usage ;;
        *) [[ -z $candidate ]] || usage; candidate=$1; shift ;;
    esac
done
[[ -n $candidate ]] || usage
case $failure in none|place|health) ;; *) usage ;; esac
if [[ $plan_only == 1 ]]; then
    valid_state "$supplied_state" || usage
    target=$supplied_state
    if [[ $enable_autostart == 1 ]]; then target=loaded=1,disabled=0,running=1; fi
    plan_deployment "$supplied_state" "$target" "$failure"
    exit 0
fi
# Synthetic states/failures cannot leak into real execution.
[[ -z $supplied_state && $failure == none ]] || usage
case ${REVERIE_DEPLOY_FAULT:-} in ''|place) ;; *) usage ;; esac

script_dir=$(cd "$(dirname "$0")" && pwd)
install=/Applications/Reverie.app
previous=/Applications/Reverie.app.prev
agent_plist="$HOME/Library/LaunchAgents/com.local.reverie.plist"
user_id=$(id -u)
domain="gui/$user_id"
service="$domain/com.local.reverie"
stage= original= actual_loaded=0 recovery_armed=0 current_step=SETUP

is_running() { /usr/bin/pgrep -u "$user_id" -x Reverie >/dev/null; }

read_loaded() {
    # Failure of the GUI domain itself must not masquerade as an unloaded service.
    /bin/launchctl print "$domain" >/dev/null || return
    if /bin/launchctl print "$service" >/dev/null 2>&1; then
        actual_loaded=1
    else
        actual_loaded=0
    fi
}

read_state() {
    local disabled_output disabled running=0
    read_loaded || return
    disabled_output=$(/bin/launchctl print-disabled "$domain") || return
    disabled=$(printf '%s\n' "$disabled_output" | /usr/bin/awk '
        /"com[.]local[.]reverie"[[:space:]]*=>/ {
            if (++seen > 1) exit 1
            # macOS 27 prints enabled / disabled; older releases printed true / false.
            if ($NF == "true" || $NF == "disabled") value=1
            else if ($NF == "false" || $NF == "enabled") value=0
            else exit 1
        }
        END { if (!seen) print 0; else print value }
    ') || return
    [[ $disabled == 0 || $disabled == 1 ]] || return 1
    if is_running; then running=1; fi
    printf 'loaded=%s,disabled=%s,running=%s\n' "$actual_loaded" "$disabled" "$running"
}

wait_running() {
    local wanted=$1 attempt running
    for ((attempt=0; attempt<50; attempt++)); do
        running=0
        if is_running; then running=1; fi
        [[ $running == "$wanted" ]] && return 0
        sleep 0.1 || return
    done
    echo "Timed out waiting for running=$wanted" >&2
    return 1
}

# All deployment actions are translated here; no eval or shell-text execution.
# Every fallible subcommand propagates failure, including during EXIT recovery.
run_step() {
    local action=$1 detail=${2:-} signature observed attempt
    current_step=$action
    printf '%s%s\n' "$action" "${detail:+ $detail}"
    case $action in
        VERIFY_CANDIDATE)
            [[ -d $candidate && -d $install && ! -L $install ]] || return 1
            # A stale backup is evidence of an unfinished deployment; never overwrite it.
            [[ ! -e $previous && ! -L $previous ]] || {
                echo "Existing $previous requires manual recovery" >&2; return 1;
            }
            [[ -f $agent_plist && -f $script_dir/check-window.swift ]] || return 1
            stage=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/reverie-deploy.XXXXXX") || return
            /usr/bin/ditto "$candidate" "$stage/Reverie.app" || return
            [[ -x $stage/Reverie.app/Contents/MacOS/Reverie ]] || return 1
            /usr/bin/codesign --verify --deep --strict "$stage/Reverie.app" || return
            signature=$(/usr/bin/codesign -dvv "$stage/Reverie.app" 2>&1) || return
            printf '%s\n' "$signature" | /usr/bin/grep -qx "Authority=${REVERIE_SIGN_IDENTITY:-Reverie Local}" || return
            [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$stage/Reverie.app/Contents/Info.plist") == com.local.reverie ]] || return 1
            ;;
        RECORD_STATE) original=$(read_state) || return ;;
        ARM_RECOVERY) recovery_armed=1 ;;
        MOVE_ASIDE) /bin/mv "$install" "$previous" || return ;;
        CHECK_LOADED) read_loaded || return ;;
        BOOTOUT)
            # Recheck also on the normal path in case the service disappeared meanwhile.
            read_loaded || return
            if [[ $actual_loaded == 1 ]]; then /bin/launchctl bootout "$service" || return; fi
            # bootout returns before launchd finishes tearing the job down; a bootstrap that lands in
            # that window fails with "Input/output error". Wait until the service is really gone.
            local i
            for i in $(seq 1 30); do
                read_loaded || return
                [[ $actual_loaded == 0 ]] && break
                /bin/sleep 0.5
            done
            ;;
        KILL_LEFTOVER)
            if is_running; then
                /usr/bin/pkill -TERM -u "$user_id" -x Reverie || { is_running && return 1; }
                if ! wait_running 0; then
                    /usr/bin/pkill -KILL -u "$user_id" -x Reverie || { is_running && return 1; }
                    wait_running 0 || return
                fi
            fi
            ;;
        PLACE_CANDIDATE)
            [[ ${REVERIE_DEPLOY_FAULT:-} != place ]] || return 1
            /usr/bin/ditto "$stage/Reverie.app" "$install" || return
            ;;
        ENABLE) /bin/launchctl enable "$service" || return ;;
        DISABLE) /bin/launchctl disable "$service" || return ;;
        BOOTSTRAP)
            # Same race from the other side: retry a few times if launchd is still busy.
            local attempt
            for attempt in 1 2 3 4 5 6; do
                /bin/launchctl bootstrap "$domain" "$agent_plist" && break
                [[ $attempt == 6 ]] && return 1
                /bin/sleep 1
            done
            ;;
        OPEN) /usr/bin/open -a "$install" || return ;;
        HEALTH_CHECK)
            wait_running 1 || return
            sleep 2 || return
            /usr/bin/swift "$script_dir/check-window.swift" --assert-covers-target || return
            ;;
        QUIT_APP)
            # Sending quit to an absent application can launch it; guard the Apple Event.
            if is_running; then
                /usr/bin/osascript -e 'tell application id "com.local.reverie" to quit' || return
            fi
            wait_running 0 || return
            ;;
        VERIFY_STATE)
            for ((attempt=0; attempt<50; attempt++)); do
                observed=$(read_state) || return
                [[ $observed == "$detail" ]] && return 0
                sleep 0.1 || return
            done
            echo "State mismatch: expected $detail; observed $observed" >&2
            return 1
            ;;
        REMOVE_NEW)
            # mv may have failed before creating .prev. In that case the original stays.
            if [[ -d $previous && ! -L $previous ]]; then /bin/rm -rf "$install" || return; fi
            ;;
        RESTORE_PREV)
            if [[ -d $previous && ! -L $previous ]]; then
                [[ ! -e $install && ! -L $install ]] || return 1
                /bin/mv "$previous" "$install" || return
            else
                [[ -d $install && ! -L $install ]] || return 1
            fi
            ;;
        DISARM_RECOVERY) recovery_armed=0 ;;
        DELETE_PREV) /bin/rm -rf "$previous" || return ;;
        *) echo "Unknown action: $action" >&2; return 2 ;;
    esac
    return 0
}

execute_plan() {
    local plan=$1 skip_preflight=${2:-0} action detail
    while IFS=' ' read -r action detail; do
        if [[ $skip_preflight == 1 && ( $action == VERIFY_CANDIDATE || $action == RECORD_STATE ) ]]; then
            continue
        fi
        run_step "$action" "$detail" || return
    done <<< "$plan"
}

on_exit() {
    local status=$1 failed_step=$current_step recovery_status=0 recovery_plan
    trap - EXIT
    # Do not interrupt recovery halfway through; a second error must not recurse.
    trap '' HUP INT TERM
    set +e
    if [[ $recovery_armed == 1 ]]; then
        [[ $status != 0 ]] || status=1
        echo "Deployment failed at $failed_step (exit $status); restoring $original" >&2
        run_step CHECK_LOADED
        recovery_status=$?
        if [[ $recovery_status == 0 ]]; then
            recovery_plan=$(plan_recovery "$original" "$actual_loaded")
            execute_plan "$recovery_plan"
            recovery_status=$?
        fi
        if [[ $recovery_status != 0 ]]; then
            echo "Recovery failed at $current_step; inspect $install and $previous before retrying" >&2
        else
            echo "Original bundle/state restored: $original" >&2
        fi
    elif [[ $status != 0 ]]; then
        echo "Deployment stopped at $failed_step (exit $status)" >&2
    fi
    if [[ -n $stage ]]; then /bin/rm -rf "$stage"; fi
    exit "$status"
}

# Before ARM_RECOVERY this trap only cleans staging. There are no system mutations.
trap 'on_exit $?' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
run_step VERIFY_CANDIDATE
run_step RECORD_STATE
target=$original
if [[ $enable_autostart == 1 ]]; then target=loaded=1,disabled=0,running=1; fi
deployment_plan=$(plan_deployment "$original" "$target" none)
execute_plan "$deployment_plan" 1
