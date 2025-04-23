#!/bin/sh
# entrypoint.sh
set -e

# Mount GCS bucket using service account credentials
gcsfuse --implicit-dirs ${GCS_BUCKET_NAME} /data

# Start n8n
exec n8n
