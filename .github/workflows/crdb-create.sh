#!/bin/bash

CONFIG_JSON="redis_config.json"
CONFIG_YAML="redis_config.yaml"
CLUSTER_FILE="clusters.txt"
MAX_CLUSTERS=4

# Load .env if available
[[ -f .env ]] && source .env

# Helper to prompt with default
prompt() {
  local prompt_text="$1"
  local default="$2"
  read -p "$prompt_text [$default]: " input
  echo "${input:-$default}"
}

# Collect config inputs with defaults or .env values
DBNAME=$(prompt "Enter DB Name" "${DBNAME:-example-db}")
REP=$(prompt "Replication factor" "${REP:-3}")
MEM=$(prompt "Memory size (e.g. 1gb)" "${MEM:-1gb}")
MAXCONN=$(prompt "Max connections" "${MAXCONN:-5000}")
REDIS_PASS=$(prompt "Redis password" "${REDIS_PASS:-supersecure}")
SYNC_POLICY=$(prompt "AOF policy" "${SYNC_POLICY:-appendfsync-every-sec}")
CA_CERT=$(prompt "Path to CA cert" "${CA_CERT:-/path/to/ca_cert.pem}")
SCRDBUSER=$(prompt "Redis DB Username" "${SCRDBUSER:-admin}")
SCRDBPASS=$(prompt "Redis DB Password" "${SCRDBPASS:-password}")

# Validate clusters.txt
if [[ ! -f "$CLUSTER_FILE" ]]; then
  echo "ERROR: Cluster input file '$CLUSTER_FILE' not found."
  exit 1
fi

mapfile -t cluster_lines < "$CLUSTER_FILE"
TOTAL=${#cluster_lines[@]}

if (( TOTAL == 0 )); then
  echo "ERROR: No clusters in file."
  exit 1
elif (( TOTAL > MAX_CLUSTERS )); then
  echo "ERROR: Too many clusters. Max is $MAX_CLUSTERS. Found: $TOTAL"
  exit 1
fi

# Parse clusters
declare -a CLUSTERS
declare -a CLUST_NAMES
for line in "${cluster_lines[@]}"; do
  read -r url name <<< "$line"
  CLUSTERS+=("$url")
  CLUST_NAMES+=("$name")
done

# Build JSON
cat <<EOF > "$CONFIG_JSON"
{
  "default_db_config": {
    "name": "$DBNAME",
    "replication": $REP,
    "memory_size": "$MEM",
    "max_connections": $MAXCONN,
    "authentication": true,
    "redis_pass": "$REDIS_PASS",
    "aof_policy": "$SYNC_POLICY"
  },
  "instances": [
EOF

# Loop through each instance
for i in "${!CLUSTERS[@]}"; do
  CLUSTER_URL="${CLUSTERS[$i]}"
  CLUSTER_NAME="${CLUST_NAMES[$i]}"
  cat <<EOL >> "$CONFIG_JSON"
    {
      "cluster": {
        "url": "$CLUSTER_URL",
        "credentials": {
          "username": "$SCRDBUSER",
          "password": "$SCRDBPASS"
        },
        "name": "$CLUSTER_NAME"
      },
      "db_config": {
        "tls_mode": "enabled",
        "enforce_client_authentication": "enabled",
        "client_cert_subject_validation_type": "full_subject",
        "authorized_subjects": [
          {
            "C": "US",
            "CN": "\${CN}",
            "L": "\${L}",
            "O": "Wells Fargo",
            "OU": ["\${OU[0]}"],
            "ST": "\${ST}"
          }
        ],
        "authentication_ssl_client_certs": [
          {
            "client_cert": "$CA_CERT"
          }
        ],
        "compression": 6,
        "name": "$DBNAME",
        "encryption": true
      }
    }$( [[ $i -lt $((TOTAL-1)) ]] && echo "," )
EOL
done

# Finalize JSON
echo "  ]" >> "$CONFIG_JSON"
echo "}" >> "$CONFIG_JSON"

# Validate JSON
if command -v jq &>/dev/null; then
  jq . "$CONFIG_JSON" > /dev/null && echo "✅ Valid JSON: $CONFIG_JSON" || echo "❌ JSON validation failed!"
else
  echo "ℹ️ jq not installed. Skipping validation."
fi

# Optional YAML output if yq is installed
if command -v yq &>/dev/null; then
  yq -P . "$CONFIG_JSON" > "$CONFIG_YAML"
  echo "✅ YAML output written to: $CONFIG_YAML"
fi

# --- Upload to Redis Enterprise API ---
read -p "Do you want to upload config to Redis Enterprise? (y/n): " UPLOAD
if [[ "$UPLOAD" =~ ^[Yy]$ ]]; then
  API_URL=$(prompt "Enter Redis Enterprise API base URL" "https://localhost:9443")
  API_USER=$(prompt "API Username" "admin@admin.com")
  API_PASS=$(prompt "API Password" "admin")

  echo "Logging in..."
  SESSION_TOKEN=$(curl -sk -X POST "$API_URL/v1/login"     -H 'Content-Type: application/json'     -d "{"email":"$API_USER","password":"$API_PASS"}" | jq -r '.token')

  if [[ -z "$SESSION_TOKEN" || "$SESSION_TOKEN" == "null" ]]; then
    echo "❌ Login failed. Check credentials."
    exit 1
  fi

  echo "✅ Authenticated. Uploading DB config..."

  RESPONSE=$(curl -sk -X POST "$API_URL/v1/bdbs"     -H "Content-Type: application/json"     -H "Authorization: Bearer $SESSION_TOKEN"     -d @"$CONFIG_JSON")

  echo "$RESPONSE" | jq .

  if echo "$RESPONSE" | grep -q '"uid"'; then
    echo "✅ DB configuration applied successfully."
  else
    echo "❌ Failed to apply config."
  fi
fi
