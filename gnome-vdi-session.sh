#!/bin/bash

set -uo pipefail

LOG_DIR="${GNOME_VDI_LOG_DIR:-/var/log/vortice}"
SESSION_LOG="$LOG_DIR/gnome-vdi-session.log"
GNOME_RD_LOG="$LOG_DIR/gnome-remote-desktop-daemon.log"
GDM_LOG="$LOG_DIR/gdm-headless-login-session.log"
RESTART_DELAY=5

HOST_USER=$(awk -F'-' '{print $2}' /etc/hostname)
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

if [[ -z "$HOST_USER" ]]; then
    echo "ERROR: Unable to determine session user from hostname $(cat /etc/hostname)" >&2
    exit 1
fi

HOST_GROUP=$(id -gn "$HOST_USER" 2>/dev/null || true)
if [[ -z "$HOST_GROUP" ]]; then
    echo "ERROR: User $HOST_USER does not exist" >&2
    exit 1
fi

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp
    timestamp=$(date --iso-8601=seconds)
    echo "${timestamp} [${level}] ${message}" | tee -a "$SESSION_LOG"
}

prepare_logs() {
    install -d -m 0750 -o "$HOST_USER" -g "$HOST_GROUP" "$LOG_DIR"

    for logfile in "$SESSION_LOG" "$GNOME_RD_LOG" "$GDM_LOG"; do
        if [[ ! -f "$logfile" ]]; then
            install -m 0640 -o "$HOST_USER" -g "$HOST_GROUP" /dev/null "$logfile"
        else
            chown "$HOST_USER":"$HOST_GROUP" "$logfile"
        fi
    done
}

prepare_logs

terminate_requested=false
remote_pid=""
gdm_pid=""

wait_for_pid() {
    local pid=$1
    local attempts=${2:-5}
    local delay=${3:-1}

    if [[ -z "$pid" ]]; then
        return 0
    fi

    if wait "$pid" 2>/dev/null; then
        return 0
    fi

    while (( attempts > 0 )); do
        if ! kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        sleep "$delay"
        ((attempts--))
    done

    return 1
}

stop_processes() {
    for pid in "$gdm_pid" "$remote_pid"; do
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            if ! wait_for_pid "$pid" 10 1; then
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
    done
    remote_pid=""
    gdm_pid=""
}

handle_signal() {
    local signal=$1
    log INFO "Received signal ${signal}, stopping processes"
    terminate_requested=true
    stop_processes
}

trap 'handle_signal TERM' TERM
trap 'handle_signal INT' INT
trap 'stop_processes' EXIT

start_remote_desktop() {
    log INFO "Starting gnome-remote-desktop-daemon for user ${HOST_USER}"
    remote_pid=$(su -s /bin/bash - "$HOST_USER" -c "( /usr/libexec/gnome-remote-desktop-daemon --headless >> '$GNOME_RD_LOG' 2>&1 & echo \$! )")
    if [[ -z "$remote_pid" ]]; then
        log ERROR "Failed to start gnome-remote-desktop-daemon"
        return 1
    fi
    log INFO "gnome-remote-desktop-daemon started with PID ${remote_pid}"
}

start_gdm_session() {
    log INFO "Starting gdm-headless-login-session for user ${HOST_USER}"
    /usr/libexec/gdm-headless-login-session --user "$HOST_USER" >> "$GDM_LOG" 2>&1 &
    gdm_pid=$!
    if [[ -z "$gdm_pid" ]]; then
        log ERROR "Failed to start gdm-headless-login-session"
        return 1
    fi
    log INFO "gdm-headless-login-session started with PID ${gdm_pid}"
}

ensure_setup() {
    if [[ -x "${SCRIPT_DIR}/setup_grd.sh" ]]; then
        log INFO "Running setup_grd.sh"
        "${SCRIPT_DIR}/setup_grd.sh" >> "$SESSION_LOG" 2>&1
    else
        log WARN "setup_grd.sh not found in ${SCRIPT_DIR}, attempting to execute from PATH"
        if command -v setup_grd.sh >/dev/null 2>&1; then
            setup_grd.sh >> "$SESSION_LOG" 2>&1
        else
            log ERROR "setup_grd.sh is not available"
            return 1
        fi
    fi
}

run_loop() {
    while ! $terminate_requested; do
        log INFO "Preparing GNOME VDI session startup"
        ensure_setup || { log ERROR "Setup step failed, retrying in ${RESTART_DELAY}s"; sleep "$RESTART_DELAY"; continue; }

        if ! start_remote_desktop; then
            log ERROR "Remote desktop failed to start, retrying in ${RESTART_DELAY}s"
            sleep "$RESTART_DELAY"
            continue
        fi

        if ! start_gdm_session; then
            log ERROR "GDM session failed to start, stopping remote desktop"
            stop_processes
            sleep "$RESTART_DELAY"
            continue
        fi

        log INFO "GNOME VDI session components are running"

        while true; do
            if $terminate_requested; then
                log INFO "Termination requested, breaking supervision loop"
                break 2
            fi

            if [[ -n "$remote_pid" ]] && ! kill -0 "$remote_pid" 2>/dev/null; then
                log WARN "gnome-remote-desktop-daemon exited unexpectedly"
                break
            fi

            if [[ -n "$gdm_pid" ]] && ! kill -0 "$gdm_pid" 2>/dev/null; then
                if wait "$gdm_pid" 2>/dev/null; then
                    exit_code=$?
                    log WARN "gdm-headless-login-session exited with status ${exit_code}"
                else
                    log WARN "gdm-headless-login-session exited unexpectedly"
                fi
                break
            fi

            sleep 2
        done

        stop_processes

        if $terminate_requested; then
            log INFO "Termination requested during restart, exiting"
            break
        fi

        log INFO "Restarting GNOME VDI session components in ${RESTART_DELAY}s"
        sleep "$RESTART_DELAY"
    done
}

log INFO "Starting GNOME VDI session supervisor as user ${HOST_USER}"
run_loop
log INFO "GNOME VDI session supervisor exiting"
