FROM n8nio/n8n:latest

# Switch to root user to install packages
USER root

# Install necessary tools and dependencies
RUN apk update && apk add --no-cache \
    cronie \
    rsync \
    && rm -rf /var/cache/apk/*

# Copy the custom script to the container
COPY sync-sqlite-to-gcs.sh /usr/local/bin/sync-sqlite-to-gcs.sh
RUN chmod +x /usr/local/bin/sync-sqlite-to-gcs.sh

# Switch back to the non-root user (node)
USER node

# Start n8n and synchronize SQLite to GCS
CMD ["sh", "-c", "n8n start & /usr/local/bin/sync-sqlite-to-gcs.sh"]