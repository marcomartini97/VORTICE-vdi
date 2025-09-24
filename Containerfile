FROM fedora:42

RUN dnf -y update && \
    dnf -y group install "gnome-desktop" && \
    dnf -y install dbus-x11 && \
    dnf clean all

# Copy the keys present in the local folder "vdi" in /etc/
# (La copia ricorsiva è implicita con "COPY vdi /etc/")
COPY vdi /etc/vdi

# Copy the compositor start scripts start_gnome.sh setup_grd.sh in /usr/bin/
COPY start_gnome.sh /usr/bin/
COPY setup_grd.sh /usr/bin/

RUN chmod +x /usr/bin/start_gnome.sh /usr/bin/setup_grd.sh

# Copy and enable the systemD service
COPY gnome-vdi-session.service /etc/systemd/system/gnome-vdi-session.service

RUN systemctl enable gnome-vdi-session.service

# Copy optional NVIDIA driver installers placed under drivers/
COPY drivers/ /tmp/drivers/

RUN DRIVER_PATH=$(find /tmp/drivers -maxdepth 1 -type f -name 'NVIDIA-Linux-x86_64*.run' -print -quit) && \
    if [ -n "$DRIVER_PATH" ]; then \
        chmod +x "$DRIVER_PATH" && \
        "$DRIVER_PATH" --no-kernel-modules -s && \
        rm -f "$DRIVER_PATH"; \
    else \
        echo "Skipping NVIDIA driver installation; installer not provided."; \
    fi

CMD ["/usr/sbin/init"]
