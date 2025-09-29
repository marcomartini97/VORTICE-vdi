#!/bin/sh

set -eu

SESSION_USER=$(awk -F'-' '{print $2}' /etc/hostname || true)

if [ -z "$SESSION_USER" ]; then
    echo "Unable to determine VDI session user from hostname." >&2
    exit 1
fi

su -c '(
    eval "$(dbus-launch --sh-syntax)"
    grdctl --headless rdp set-tls-cert /etc/vdi/cert.pem
    grdctl --headless rdp set-tls-key /etc/vdi/key.pem
    grdctl --headless rdp set-credentials rdp rdp
    grdctl --headless rdp enable
)' "$SESSION_USER"

