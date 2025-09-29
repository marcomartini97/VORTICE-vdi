FROM alpine:3.22.1

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

RUN apk update && \
    apk add --no-cache \
        bash \
        ca-certificates \
        dbus \
        dbus-x11 \
        freerdp \
        gdm \
        gnome-session \
        gnome-shell \
        gnome-remote-desktop \
	pipewire \
	firefox \
	fuse \
	fuse3 \
	polkit \
	polkit-common \ 
	gobject-introspection \
        mesa-dri-gallium \
	vulkan-loader \
	mesa-demos \
        openrc \
        shadow \
        sudo \
        tzdata && \
    rc-update add dbus default && \
    rc-update add gdm default && \
    sed -i 's/^#rc_sys=.*/rc_sys="docker"/' /etc/rc.conf && \
    mkdir -p /run/openrc && \
    touch /run/openrc/softlevel

# More Gnome stuff

RUN apk add $(apk info --quiet --depends gnome gnome-apps-core)

RUN adduser -D -S -h /var/lib/gnome-remote-desktop gnome-remote-desktop || true
RUN mkdir -p /var/lib/gnome-remote-desktop && \
    chown gnome-remote-desktop /var/lib/gnome-remote-desktop

COPY vdi /etc/vdi

RUN if [ -d /etc/vdi ]; then \
        if [ ! -f /etc/vdi/cert.pem ] || [ ! -f /etc/vdi/key.pem ]; then \
            rm -f /etc/vdi/cert.pem /etc/vdi/key.pem && \
            winpr-makecert3 -silent -path /etc/vdi -n VDI && \
            CERT_FILE=$(find /etc/vdi -maxdepth 1 -type f -name '*.crt' | head -n1) && \
            KEY_FILE=$(find /etc/vdi -maxdepth 1 -type f -name '*.key' | head -n1) && \
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

COPY start_gnome.sh /usr/bin/start_gnome.sh
COPY gnome-vdi-session.sh /usr/bin/gnome-vdi-session.sh
COPY setup_grd.sh /usr/bin/setup_grd.sh
RUN chmod +x /usr/bin/start_gnome.sh /usr/bin/gnome-vdi-session.sh /usr/bin/setup_grd.sh

COPY gnome-vdi-session.initd /etc/init.d/gnome-vdi-session
RUN chmod +x /etc/init.d/gnome-vdi-session && \
    rc-update add gnome-vdi-session default

COPY drivers/ /tmp/drivers/

RUN DRIVER_PATH=$(find /tmp/drivers -maxdepth 1 -type f -name 'NVIDIA-Linux-x86_64*.run' | head -n1) && \
    if [ -n "$DRIVER_PATH" ]; then \
        chmod +x "$DRIVER_PATH" && \
        "$DRIVER_PATH" --no-kernel-modules -s && \
        rm -f "$DRIVER_PATH"; \
    else \
        echo "Skipping NVIDIA driver installation; installer not provided."; \
    fi

CMD ["/sbin/init"]
