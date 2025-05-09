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

# Start Docker daemon in the background
dockerd &

# Wait for Docker to start (adjust sleep time if needed)
while ! docker info >/dev/null 2>&1; do
    echo "Waiting for Docker to start..."
    sleep 1
done

# # Verify Docker and Docker Compose are working
# docker --version
# docker compose version

# # Give container process time to start
# sleep 2

# If command was passed to container, execute it, otherwise run bash
if [ $# -gt 0 ]; then
    exec "$@"
else
    exec sleep infinity
fi