# VORTICE VDI OCI Image Template

This repository contains the build context for the Virtual Desktop Infrastructure (VDI) image used in the VORTICE project. The resulting OCI image boots an Alpine Linux userspace, brings up a GNOME session in headless mode, and exposes it through the GNOME Remote Desktop RDP server so that a VORTICE worker can be controlled remotely.

## What the image provides
- Installs the GNOME Desktop environment and supporting services on top of an Alpine Linux base image.
- Copies TLS material and other VDI-specific assets from `vdi/` into `/etc/vdi` inside the container.
- Configures and enables `gnome-remote-desktop` in headless RDP mode with a default `rdp/rdp` credential pair.
- Starts the compositor through an OpenRC service (`gnome-vdi-session.initd`) that runs `gnome-vdi-session.sh` during boot and restarts the stack on failure.
- Optionally installs an NVIDIA driver package when a matching installer archive is dropped in `drivers/`.

## Repository layout
- `Containerfile` – builds the Alpine-based OCI image, installs GNOME and dbus, stages VORTICE assets, enables the OpenRC service, and runs the optional NVIDIA installer if present.
- `gnome-vdi-session.sh` – headless GNOME launcher, prepares the runtime, configures GNOME Remote Desktop, and loops to relaunch the session when it exits.
- `start_gnome.sh` – legacy launcher kept for manual testing and backward compatibility.
- `setup_grd.sh` – runs as the derived user to configure `gnome-remote-desktop` via `grdctl`, loading `cert.pem`/`key.pem` from `/etc/vdi` and enabling password-protected RDP access.
- `gnome-vdi-session.initd` – OpenRC unit activated at boot to start and supervise the headless GNOME session; restarts the stack automatically if it exits.
- `vdi/` – placeholder directory; populate it with TLS assets (at minimum `cert.pem` and `key.pem`) and any extra configuration that needs to land in `/etc/vdi` at build time.
- `drivers/` – drop proprietary GPU driver installers here. A file matching `NVIDIA-Linux-x86_64*.run` will be executed during the build; `.gitkeep` keeps the directory in source control.

## Required inputs before building
- (Optional) Provide TLS material: place the server certificate and key as `vdi/cert.pem` and `vdi/key.pem`. They are copied verbatim into the image.
- Decide on RDP credentials: the default `rdp/rdp` pair is set in `gnome-vdi-session.sh` and `setup_grd.sh` (legacy); adjust the script if another username/password is required.
- Ensure the image defines the VDI user: `gnome-vdi-session.sh` expects the container hostname to be `vdi-<username>` and that the corresponding Linux user already exists in the OS image. Add user creation steps to the `Containerfile` or inject them through your orchestration pipeline.

## Building the image
Use any OCI build tool (e.g. Podman or Docker) to produce the image:

```
podman build -t vortice-vdi .
```

The build will automatically install GNOME, copy the VORTICE assets, enable the systemd unit, and optionally install a provided NVIDIA driver.

## Running the image
Run the freshly built image on a host that already defines the `marco` user: configure the hostname as `vdi-marco` so the VDI session picks the correct account.

```sh
podman run --name vdi-marco \
    --volume /var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket \
    --volume /home:/home \
    --volume /etc/passwd:/etc/passwd \
    --volume /etc/group:/etc/group\
    --volume /etc/shadow:/etc/shadow \
    --hostname vdi-marco \
    --volume /etc/group:/etc/group \
    --device /dev/fuse:/dev/fuse \
    --cap-add SYS_ADMIN \
    -t \
    vortex-vdi
```

Adjust paths and the final image reference if your environment differs.
