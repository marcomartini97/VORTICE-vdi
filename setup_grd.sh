#!/bin/sh

set -eu

SESSION_USER=$(awk -F'-' '{print $2}' /etc/hostname || true)

if [ -z "$SESSION_USER" ]; then
    echo "Unable to determine VDI session user from hostname." >&2
    exit 1
fi

DEFAULT_IFACE=$(ip route show default | awk 'NR==1 {for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i+1); exit}}')

if [ -z "${DEFAULT_IFACE:-}" ]; then
    echo "Unable to detect default network interface." >&2
    exit 1
fi

IP_ADDRESS=$(ip -o -4 addr show dev "$DEFAULT_IFACE" | awk 'NR==1 {split($4, a, "/"); print a[1]}')

if [ -z "${IP_ADDRESS:-}" ]; then
    echo "Unable to determine IP address for interface $DEFAULT_IFACE." >&2
    exit 1
fi

generate_random_string() {
    length="$1"
    LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$length"
}

USERNAME=$(generate_random_string 16)
PASSWORD=$(generate_random_string 32)

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "Failed to generate credentials." >&2
    exit 1
fi

export GRD_USERNAME="$USERNAME"
export GRD_PASSWORD="$PASSWORD"

su -c '(
    eval "$(dbus-launch --sh-syntax)"
    grdctl --headless rdp set-tls-cert /etc/vdi/cert.pem
    grdctl --headless rdp set-tls-key /etc/vdi/key.pem
    grdctl --headless rdp set-credentials "$GRD_USERNAME" "$GRD_PASSWORD"
    grdctl --headless rdp enable
)' "$SESSION_USER"

printf '{"ip":"%s","username":"%s","password":"%s"}\n' "$IP_ADDRESS" "$USERNAME" "$PASSWORD"
