#!/bin/bash

# Generate a 256-bit (32-byte) random key using OpenSSL
# This creates a strong key suitable for Cloud SQL instance encryption

echo "Generating a 256-bit encryption key for Google Cloud SQL..."

# Generate the binary key
openssl rand -out cloud_sql_encryption_key.bin 32

# Create a base64 encoded version for easier handling in some cases
openssl base64 -in cloud_sql_encryption_key.bin -out cloud_sql_encryption_key.base64.txt

# Display information about the generated key
echo "Encryption key generated successfully!"
echo "Binary key saved as: cloud_sql_encryption_key.bin"
echo "Base64 encoded key saved as: cloud_sql_encryption_key.base64.txt"

# Display the base64 encoded key (for convenience)
echo ""
echo "Base64 encoded key:"
cat cloud_sql_encryption_key.base64.txt

echo ""
echo "IMPORTANT: Store this key securely. If you lose it, you cannot recover encrypted data."
echo "Consider storing it in a secure key management system like Google Cloud KMS."
