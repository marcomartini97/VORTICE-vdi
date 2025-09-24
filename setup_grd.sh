#!/bin/bash

# This is based on hostname! Don't change it 
su -c '(
    eval "$(dbus-launch --sh-syntax)"
    grdctl --headless rdp set-tls-cert /etc/vdi/cert.pem
    grdctl --headless rdp set-tls-key /etc/vdi/key.pem
    grdctl --headless rdp set-credentials rdp rdp
    grdctl --headless rdp enable
)' $(awk -F'-' '{print $2}' /etc/hostname)

