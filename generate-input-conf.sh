#!/bin/bash

REQUEST_FILE="request_form.txt"
OUTPUT_FILE="input.conf"

if [[ ! -f "$REQUEST_FILE" ]]; then
  echo "❌ Request form '$REQUEST_FILE' not found."
  exit 1
fi

APP_NAME=$(grep -i "App Name:" "$REQUEST_FILE" | cut -d':' -f2- | xargs)
SUB_APP_ID=$(grep -i "Sub App ID:" "$REQUEST_FILE" | cut -d':' -f2- | xargs)
ENV=$(grep -i "Environment:" "$REQUEST_FILE" | cut -d':' -f2- | xargs)
SEQ_NO=$(grep -i "Sequence Number:" "$REQUEST_FILE" | cut -d':' -f2- | xargs)
CN=$(grep -i "Common Name" "$REQUEST_FILE" | cut -d':' -f2- | xargs)
OU=$(grep -i "Organization Unit" "$REQUEST_FILE" | cut -d':' -f2- | xargs)
USERNAME=$(grep -i "Username:" "$REQUEST_FILE" | cut -d':' -f2- | xargs)
PASSWORD=$(grep -i "Password:" "$REQUEST_FILE" | cut -d':' -f2- | xargs)

cat <<EOF > "$OUTPUT_FILE"
APP_NAME="$APP_NAME"
SUB_APP_ID="$SUB_APP_ID"
ENV="$ENV"
SEQ_NO=$SEQ_NO
CN="$CN"
OU="$OU"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
EOF

echo "✅ input.conf created successfully:"
cat "$OUTPUT_FILE"
