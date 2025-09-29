#!/bin/bash 
# RUN THIS ONE AS ROOT
sudo mkdir -p /tmp/.X11-unix && sudo chmod 1777 /tmp/.X11-unix   # for Xwayland


# RUN THESE as user taken from the hostname after the dash e-g vdi-marco the user is marco
export XDG_RUNTIME_DIR=/tmp/xdg-runtime-$(id -u)
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_CLASS=user
export XDG_SESSION_DESKTOP=gnome
export XDG_CURRENT_DESKTOP=GNOME

/usr/lib/polkit-1/polkitd --no-debug &

dbus-run-session -- bash -lc '
pipewire & wireplumber &
gnome-shell --wayland --headless &
grdctl --headless rdp set-tls-cert /etc/vdi/cert.pem
grdctl --headless rdp set-tls-key /etc/vdi/key.pem
grdctl --headless rdp set-credentials rdp rdp
/usr/libexec/gnome-remote-desktop-daemon --headless '
