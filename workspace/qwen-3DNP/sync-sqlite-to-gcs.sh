#!/bin/sh

# Define the database file and the GCS path
DB_FILE="/home/node/.n8n/database.sqlite"
GCS_PATH="gs://n8n-database-bucket/database.sqlite"

# Set up the cron job to synchronize the SQLite database to GCS every minute
echo "* * * * * rsync $DB_FILE $GCS_PATH" >> /etc/periodic/1min/sync-sqlite-to-gcs
chmod +x /etc/periodic/1min/sync-sqlite-to-gcs

# Start the cron service
crond -f -l 2 > /dev/null 2>&1 &

# Wait for n8n to start properly
sleep 30

# Initial synchronization
rsync $DB_FILE $GCS_PATH