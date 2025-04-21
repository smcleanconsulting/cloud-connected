#!/bin/bash
# entrypoint.sh - Prepare podman-in-podman environment

# This script runs as root before switching to the cloud-user

# Make mount points shared
mount --make-rshared /

# Configure system-wide storage driver
mkdir -p /etc/containers
cat > /etc/containers/storage.conf << EOF
[storage]
driver = "vfs"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"
EOF

# Give container process time to start
sleep 2

# If command was passed to container, execute it, otherwise run bash
if [ $# -gt 0 ]; then
    exec "$@"
else
    exec sleep infinity
fi