#!/bin/sh

set -eu

HOSTNAME_USER=$(awk -F'-' '{print $2}' /etc/hostname || true)
USER=${HOSTNAME_USER:-}

if [ -z "$USER" ]; then
    echo "Unable to determine VORTICE session user from hostname." >&2
    exit 1
fi

echo "Starting GNOME as $USER"

setup_grd.sh

GRD_DAEMON=$(command -v gnome-remote-desktop-daemon 2>/dev/null || true)
if [ -z "$GRD_DAEMON" ]; then
    ALT_GNRD="/usr/libexec/gnome-remote-desktop-daemon"
    if [ -x "$ALT_GNRD" ]; then
        GRD_DAEMON="$ALT_GNRD"
    else
        echo "gnome-remote-desktop-daemon not found" >&2
        exit 1
    fi
fi

GDM_HEADLESS=$(command -v gdm-headless-login-session 2>/dev/null || true)
if [ -z "$GDM_HEADLESS" ]; then
    ALT_GDM="/usr/libexec/gdm-headless-login-session"
    if [ -x "$ALT_GDM" ]; then
        GDM_HEADLESS="$ALT_GDM"
    else
        echo "gdm-headless-login-session not found" >&2
        exit 1
    fi
fi

su -c "(
    $GRD_DAEMON --headless &
)" "$USER"

exec "$GDM_HEADLESS" --user "$USER"
