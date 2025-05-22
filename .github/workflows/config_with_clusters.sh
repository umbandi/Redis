#!/bin/bash

CONFIG_FILE="config.json"
MAX_CLUSTERS=4

create_config() {
  jq -n \
    --arg app_name "MyApp" \
    --arg env "development" \
    --arg version "1.0.0" \
    --argjson debug true \
    '{
      application: {
        name: $app_name,
        version: $version
      },
      environment: $env,
      settings: {
        debug: $debug
      },
      clusters: []
    }' > "$CONFIG_FILE"
  echo "Config file created: $CONFIG_FILE"
}

get_config_value() {
  jq -r "$1" "$CONFIG_FILE"
}

set_config_value() {
  key="$1"
  value="$2"
  tmp=$(mktemp)
  jq "$key = $value" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
  echo "Updated: $key = $value"
}

delete_config_key() {
  key="$1"
  tmp=$(mktemp)
  jq "del($key)" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
  echo "Deleted key: $key"
}

add_cluster() {
  cluster_name="$1"
  cluster_region="$2"

  if [[ -z "$cluster_name" || -z "$cluster_region" ]]; then
    echo "Usage: $0 add-cluster <name> <region>"
    return 1
  fi

  current_count=$(jq '.clusters | length' "$CONFIG_FILE")
  if (( current_count >= MAX_CLUSTERS )); then
    echo "Cannot add more than $MAX_CLUSTERS clusters."
    return 1
  fi

  new_cluster=$(jq -n \
    --arg name "$cluster_name" \
    --arg region "$cluster_region" \
    '{name: $name, region: $region}')

  tmp=$(mktemp)
  jq --argjson cluster "$new_cluster" '.clusters += [$cluster]' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
  echo "Cluster '$cluster_name' added."
}

list_clusters() {
  if ! jq '.clusters' "$CONFIG_FILE" &>/dev/null; then
    echo "No clusters defined."
    return 1
  fi

  echo "Configured Clusters:"
  jq -r '.clusters[] | "- \(.name) (\(.region))"' "$CONFIG_FILE"
}

show_help() {
  echo "Usage:"
  echo "  $0 create                          Create new config file"
  echo "  $0 get <jq-path>                   Get value from config"
  echo "  $0 set <jq-path> <value>           Set value in config"
  echo "  $0 delete <jq-path>                Delete key from config"
  echo "  $0 add-cluster <name> <region>     Add cluster (max 4)"
  echo "  $0 list-clusters                   List all configured clusters"
  echo ""
  echo "Examples:"
  echo "  $0 get .application.name"
  echo "  $0 set .environment '\"production\"'"
  echo "  $0 delete .settings.debug"
  echo "  $0 add-cluster cluster1 us-east-1"
}

# Main command handler
case "$1" in
  create)
    create_config
    ;;
  get)
    [[ -f $CONFIG_FILE ]] && get_config_value "$2" || echo "Config file not found."
    ;;
  set)
    [[ -f $CONFIG_FILE ]] && set_config_value "$2" "$3" || echo "Config file not found."
    ;;
  delete)
    [[ -f $CONFIG_FILE ]] && delete_config_key "$2" || echo "Config file not found."
    ;;
  add-cluster)
    [[ -f $CONFIG_FILE ]] && add_cluster "$2" "$3" || echo "Config file not found."
    ;;
  list-clusters)
    [[ -f $CONFIG_FILE ]] && list_clusters || echo "Config file not found."
    ;;
  *)
    show_help
    ;;
esac
