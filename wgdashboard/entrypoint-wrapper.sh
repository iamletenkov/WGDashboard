#!/bin/bash
# Wrapper: ensure dashboard_api_key stays enabled after entrypoint sets up the ini
# The original entrypoint is sourced so all its functions and logic run normally.
# After setup, we patch the ini before gunicorn reads it.

config_file="/data/wg-dashboard.ini"

# Run the original entrypoint in the background
/bin/bash /entrypoint.sh &
ENTRY_PID=$!

# Wait for gunicorn to start (ini file is ready by then)
sleep 5

# Ensure dashboard_api_key is enabled
if [ -f "$config_file" ]; then
  if grep -q "^[[:space:]]*dashboard_api_key[[:space:]]*=" "$config_file"; then
    current=$(grep "^[[:space:]]*dashboard_api_key[[:space:]]*=" "$config_file" | cut -d= -f2- | xargs)
    if [ "$current" != "true" ]; then
      echo "[wrapper] Restoring dashboard_api_key = true (was: $current)"
      sed -i "/^\[Server\]/,/^\[/{s|^[[:space:]]*dashboard_api_key[[:space:]]*=.*|dashboard_api_key = true|}" "$config_file"
    else
      echo "[wrapper] dashboard_api_key is already true"
    fi
  else
    echo "[wrapper] dashboard_api_key not found, adding to [Server]"
    sed -i "/^\[Server\]/a dashboard_api_key = true" "$config_file"
  fi
fi

# Follow the entrypoint process
wait $ENTRY_PID
