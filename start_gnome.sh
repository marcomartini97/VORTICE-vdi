#!/bin/bash

# This is based on hostname! Don't change it
USER=$(awk -F'-' '{print $2}' /etc/hostname)
echo "Starting GNOME as $USER"
setup_grd.sh
su -c '(
    /usr/libexec/gnome-remote-desktop-daemon --headless &
)' $USER
/usr/libexec/gdm-headless-login-session --user $USER
