#!/bin/bash

# Set the GCS bucket name from environment variable
GCS_BUCKET=${GCS_BUCKET:-"n8n-database"}

# Path to the SQLite database
DB_PATH="/home/node/.n8n/database.sqlite"

# Sync database from GCS if it exists
if gsutil -q stat gs://${GCS_BUCKET}/database.sqlite; then
  echo "Downloading database from gs://${GCS_BUCKET}/database.sqlite"
  gsutil cp gs://${GCS_BUCKET}/database.sqlite ${DB_PATH}
else
  echo "No existing database found in GCS bucket"
fi

# Start n8n in the background
n8n start &
N8N_PID=$!

# Function to handle sync to GCS
sync_to_gcs() {
  echo "Syncing database to GCS bucket"
  gsutil cp ${DB_PATH} gs://${GCS_BUCKET}/database.sqlite
}

# Set up trap to sync on exit
trap sync_to_gcs EXIT

# Sync database to GCS periodically
while true; do
  sleep 300  # Sync every 5 minutes
  sync_to_gcs
done &

# Wait for n8n to exit
wait ${N8N_PID}