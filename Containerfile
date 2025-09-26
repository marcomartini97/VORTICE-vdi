FROM fedora:42

RUN dnf -y update && \
    dnf -y group install "gnome-desktop" && \
    dnf -y install dbus-x11 freerdp && \
    dnf clean all

# Copy the keys present in the local folder "vdi" in /etc/
# (La copia ricorsiva è implicita con "COPY vdi /etc/")
COPY vdi /etc/vdi

# Create self signed keys and certificates if not available
RUN if [ -d /etc/vdi ]; then \
        if [ ! -f /etc/vdi/cert.pem ] || [ ! -f /etc/vdi/key.pem ]; then \
            rm -f /etc/vdi/cert.pem /etc/vdi/key.pem && \
            winpr-makecert -silent -path /etc/vdi -n VDI && \
            CERT_FILE=$(find /etc/vdi -maxdepth 1 -type f -name '*.crt' -print -quit) && \
            KEY_FILE=$(find /etc/vdi -maxdepth 1 -type f -name '*.key' -print -quit) && \
            if [ -n "$CERT_FILE" ] && [ -n "$KEY_FILE" ]; then \
                mv "$CERT_FILE" /etc/vdi/cert.pem && \
                mv "$KEY_FILE" /etc/vdi/key.pem && \
                chown gnome-remote-desktop /etc/vdi/cert.pem && \
                chown gnome-remote-desktop /etc/vdi/key.pem; \
            else \
                echo 'winpr-makecert did not produce expected certificate files.' >&2 && \
                exit 1; \
            fi; \
        fi; \
    fi

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
