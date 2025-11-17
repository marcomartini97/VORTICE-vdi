podman run -d \
  --name vdi-marco \
  --hostname vdi-marco \
  --log-driver journald \
  --cap-add CAP_AUDIT_CONTROL \
  --cap-add CAP_NET_ADMIN \
  --cap-add CAP_SYS_ADMIN \
  --cap-add CAP_SYS_NICE \
  --network vortice-network \
  --cap-add CAP_SYS_PTRACE \
  --device /dev/bus/usb/002/001 \
  --pids-limit 0 \
  --device /dev/fuse \
  --device /dev/dri/renderD128 \
  --device /dev/nvidia-caps \
  --device /dev/nvidiactl \
  --device /dev/nvidia0 \
  --device /dev/nvidia-modeset \
  --device /dev/nvidia-uvm \
  --device /dev/nvidia-uvm-tools \
  --mount type=bind,src=/etc/passwd,dst=/etc/passwd \
  --mount type=bind,src=/etc/group,dst=/etc/group \
  --mount type=bind,src=/etc/shadow,dst=/etc/shadow \
  --mount type=bind,src=/home,dst=/home \
  localhost/vortice-vdi:latest \
  /usr/sbin/init
