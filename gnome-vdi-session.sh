#!/bin/bash
set -euo pipefail

SERVICE_TAG="gnome-vdi-session"

log() {
    local message="$*"
    echo "[$SERVICE_TAG] $message"
    if command -v logger >/dev/null 2>&1; then
        logger -t "$SERVICE_TAG" "$message"
    fi
}

SESSION_USER=$(awk -F'-' 'NR==1 {print $2}' /etc/hostname 2>/dev/null || true)
if [ -z "$SESSION_USER" ]; then
    log "Unable to determine VDI session user from hostname"
    exit 1
fi

if ! id "$SESSION_USER" >/dev/null 2>&1; then
    log "User $SESSION_USER does not exist"
    exit 1
fi

prepare_runtime() {
    mkdir -p /tmp/.X11-unix
    chmod 1777 /tmp/.X11-unix
}

POLKIT_PID=""

start_polkitd() {
    if pgrep -x polkitd >/dev/null 2>&1; then
        return
    fi

    local polkit_bin="/usr/lib/polkit-1/polkitd"
    if [ ! -x "$polkit_bin" ]; then
        log "polkitd binary not found at $polkit_bin; skipping launch"
        return
    fi

    "$polkit_bin" --no-debug &
    POLKIT_PID=$!
    log "Started polkitd (pid ${POLKIT_PID})"
}

stop_polkitd() {
    if [ -n "$POLKIT_PID" ] && kill -0 "$POLKIT_PID" 2>/dev/null; then
        kill "$POLKIT_PID" 2>/dev/null || true
        wait "$POLKIT_PID" 2>/dev/null || true
        POLKIT_PID=""
    fi
}

SESSION_CHILD_PID=""
STOP_REQUESTED=0

stop_child() {
    if [ -n "$SESSION_CHILD_PID" ] && kill -0 "$SESSION_CHILD_PID" 2>/dev/null; then
        kill -TERM "$SESSION_CHILD_PID" 2>/dev/null || true
        kill -TERM -- -"$SESSION_CHILD_PID" 2>/dev/null || true
        wait "$SESSION_CHILD_PID" 2>/dev/null || true
    fi
    SESSION_CHILD_PID=""
}

handle_stop() {
    STOP_REQUESTED=1
    stop_child
}

finalize() {
    stop_child
    stop_polkitd
}

trap handle_stop INT TERM
trap finalize EXIT

run_session_once() {
    su - "$SESSION_USER" -s /bin/bash <<'EOSU'
set -euo pipefail

export XDG_RUNTIME_DIR="/tmp/xdg-runtime-$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

export XDG_SESSION_TYPE=wayland
export XDG_SESSION_CLASS=user
export XDG_SESSION_DESKTOP=gnome
export XDG_CURRENT_DESKTOP=GNOME

if ! command -v dbus-run-session >/dev/null 2>&1; then
    echo "dbus-run-session not found" >&2
    exit 1
fi

dbus-run-session -- bash <<'EOSB'
set -euo pipefail

find_binary() {
    command -v "$1" 2>/dev/null || true
}

PIPEWIRE_BIN=$(find_binary pipewire)
WIREPLUMBER_BIN=$(find_binary wireplumber)
GNOME_SHELL_BIN=$(find_binary gnome-shell)
GRDCTL_BIN=$(find_binary grdctl)
GNOME_RD_BIN=$(find_binary gnome-remote-desktop-daemon)

if [ -z "$PIPEWIRE_BIN" ]; then
    echo "pipewire not found" >&2
    exit 1
fi
if [ -z "$WIREPLUMBER_BIN" ]; then
    echo "wireplumber not found" >&2
    exit 1
fi
if [ -z "$GNOME_SHELL_BIN" ]; then
    echo "gnome-shell not found" >&2
    exit 1
fi
if [ -z "$GRDCTL_BIN" ]; then
    echo "grdctl not found" >&2
    exit 1
fi
if [ -z "$GNOME_RD_BIN" ]; then
    if [ -x "/usr/libexec/gnome-remote-desktop-daemon" ]; then
        GNOME_RD_BIN="/usr/libexec/gnome-remote-desktop-daemon"
    else
        echo "gnome-remote-desktop-daemon not found" >&2
        exit 1
    fi
fi

PIPEWIRE_PID=""
WIREPLUMBER_PID=""
GNOME_SHELL_PID=""

cleanup_children() {
    for pid in "$GNOME_SHELL_PID" "$WIREPLUMBER_PID" "$PIPEWIRE_PID"; do
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done
}

trap cleanup_children EXIT

"$PIPEWIRE_BIN" &
PIPEWIRE_PID=$!

"$WIREPLUMBER_BIN" &
WIREPLUMBER_PID=$!

"$GNOME_SHELL_BIN" --wayland --headless &
GNOME_SHELL_PID=$!

"$GRDCTL_BIN" --headless rdp set-tls-cert /etc/vdi/cert.pem
"$GRDCTL_BIN" --headless rdp set-tls-key /etc/vdi/key.pem
"$GRDCTL_BIN" --headless rdp set-credentials rdp rdp
"$GRDCTL_BIN" --headless rdp enable

"$GNOME_RD_BIN" --headless
EXIT_CODE=$?
exit "$EXIT_CODE"
EOSB
EOSU
}

prepare_runtime
start_polkitd || true

while [ "$STOP_REQUESTED" -eq 0 ]; do
    set +e
    run_session_once &
    SESSION_CHILD_PID=$!
    wait "$SESSION_CHILD_PID"
    SESSION_EXIT_CODE=$?
    set -e
    SESSION_CHILD_PID=""

    if [ "$STOP_REQUESTED" -ne 0 ]; then
        break
    fi

    if [ "$SESSION_EXIT_CODE" -eq 0 ]; then
        log "GNOME session exited cleanly; restarting in 2 seconds"
    else
        log "GNOME session exited with status $SESSION_EXIT_CODE; restarting in 2 seconds"
    fi
    sleep 2
done

log "GNOME VDI session launcher exiting"
