# Dockerfile
FROM n8nio/n8n:latest

# Install gcsfuse for GCS mount
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    lsb-release \
    && echo "deb http://packages.cloud.google.com/apt gcsfuse-bionic main" \
    | tee /etc/apt/sources.list.d/gcsfuse.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - \
    && apt-get update \
    && apt-get install -y gcsfuse

# Create mount directory
RUN mkdir /data

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
