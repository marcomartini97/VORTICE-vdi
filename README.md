# VORTICE VDI OCI Image Template

This repository contains the build context for the Virtual Desktop Infrastructure (VDI) image used in the VORTICE project. The resulting OCI image boots a Fedora userspace, brings up a GNOME session in headless mode, and exposes it through the GNOME Remote Desktop RDP server so that a VORTICE worker can be controlled remotely.

## What the image provides
- Installs the GNOME Desktop environment and supporting services on top of a Fedora 43 base image.
- Copies TLS material and other VDI-specific assets from `vdi/` into `/etc/vdi` inside the container.
- Configures and enables `gnome-remote-desktop` in headless RDP mode with a default `rdp/rdp` credential pair.
- Starts the compositor through a systemd unit (`gnome-vdi-session.service`) that runs `gnome-vdi-session.sh` during boot, supervises the GNOME headless components, and writes detailed logs under `/var/log/vortice/`.
- Optionally installs an NVIDIA driver package when a matching installer archive is dropped in `drivers/`.

## Repository layout
- `Containerfile` – builds the Fedora-based OCI image, installs GNOME and dbus, stages VORTICE assets, enables the systemd unit, and runs the optional NVIDIA installer if present.
- `gnome-vdi-session.sh` – determines the session user from the container hostname (`vdi-<username>`), prepares log files, calls `setup_grd.sh`, supervises `gnome-remote-desktop-daemon` and the GDM headless login session, and restarts them if either one exits unexpectedly.
- `setup_grd.sh` – runs as the derived user to configure `gnome-remote-desktop` via `grdctl`, loading `cert.pem`/`key.pem` from `/etc/vdi` and enabling password-protected RDP access.
- `gnome-vdi-session.service` – systemd unit activated at boot to start and supervise the headless GNOME session; restarts the stack automatically if it exits.
- `vdi/` – placeholder directory; populate it with TLS assets (at minimum `cert.pem` and `key.pem`) and any extra configuration that needs to land in `/etc/vdi` at build time.
- `drivers/` – drop proprietary GPU driver installers here. A file matching `NVIDIA-Linux-x86_64*.run` will be executed during the build; `.gitkeep` keeps the directory in source control.

## Required inputs before building
- Provide TLS material: place the server certificate and key as `vdi/cert.pem` and `vdi/key.pem`. They are copied verbatim into the image.
- Decide on RDP credentials: the default `rdp/rdp` pair is set in `setup_grd.sh`; adjust the script if another username/password is required.
- Ensure the image defines the VDI user: `gnome-vdi-session.sh` expects the container hostname to be `vdi-<username>` and that the corresponding Linux user and primary group already exist in the OS image. Add user creation steps to the `Containerfile` or inject them through your orchestration pipeline.

## Observability and troubleshooting
- `journalctl -u gnome-vdi-session.service -f` tails the supervisor logs captured by systemd. Add `-o short-precise` for high-resolution timestamps when debugging race conditions.
- Component log files live under `/var/log/vortice/`: `gnome-vdi-session.log`, `gnome-remote-desktop-daemon.log`, and `gdm-headless-login-session.log`. Follow them with `sudo tail -F /var/log/vortice/*.log` during investigations.
- `systemctl status gnome-vdi-session.service` reports the unit state and shows the latest log entries when restarts occur, which helps distinguish setup failures from runtime crashes.

## Building the image
Use any OCI build tool (e.g. Podman or Docker) to produce the image:

```
podman build -t vortice-vdi .
```

The build will automatically install GNOME, copy the VORTICE assets, enable the systemd unit, and optionally install a provided NVIDIA driver.

## Running the image with Podman
Start the image with systemd PID 1 so the GNOME supervisor unit activates automatically. The example below mirrors a validated configuration (`vdi-marco`):

```
podman run -d \
  --name vdi-marco \
  --hostname vdi-marco \
  --log-driver journald \
  --cap-add CAP_AUDIT_CONTROL \
  --cap-add CAP_NET_ADMIN \
  --cap-add CAP_SYS_ADMIN \
  --cap-add CAP_SYS_NICE \
  --cap-add CAP_SYS_PTRACE \
  --device /dev/fuse \
  --device /dev/dri/renderD128 \
  --mount type=bind,src=/etc/passwd,dst=/etc/passwd,options=rbind \
  --mount type=bind,src=/etc/group,dst=/etc/group,options=rbind \
  --mount type=bind,src=/etc/shadow,dst=/etc/shadow,options=rbind \
  --mount type=bind,src=/home,dst=/home,options=rbind \
  localhost/vortice-vdi:latest \
  /usr/sbin/init
```

- Bind-mounting `/etc/passwd`, `/etc/group`, `/etc/shadow`, and `/home` ensures the container sees the same user database and home directories as the host.
- Extra capabilities give GNOME and the remote desktop stack the permissions they require in a headless container environment.
- Device passthrough enables GPU acceleration and FUSE-based features when available.
- With `--log-driver journald`, containerwide logs appear via `journalctl -u libpod-container-vdi-marco` on the host; inside the container, use the commands listed in the observability section.
