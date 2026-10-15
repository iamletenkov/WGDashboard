#!/bin/bash
# Wrapper around the upstream entrypoint:
# - keeps dashboard_api_key enabled after the entrypoint has written the ini;
# - watchdog: Docker only restarts a container whose main process exits, and an
#   "unhealthy" status alone changes nothing. When the panel stops answering HTTP for
#   WATCHDOG_FAILS checks in a row, the watchdog ends the entrypoint, the container
#   exits and "restart: always" brings it back. Tunnels in the host kernel stay up.

config_file="/data/wg-dashboard.ini"
port="${wgd_port:-5000}"
interval="${WATCHDOG_INTERVAL:-30}"
fails_allowed="${WATCHDOG_FAILS:-4}"
grace="${WATCHDOG_GRACE:-90}"

/bin/bash /entrypoint.sh &
ENTRY_PID=$!
# PID 1 ignores SIGTERM without a handler: pass "docker stop" on to the entrypoint.
trap 'kill -TERM "$ENTRY_PID" 2>/dev/null' TERM INT

# The ini is ready once gunicorn has started.
sleep 5

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

watchdog() {
  sleep "$grace"
  local fails=0
  while kill -0 "$ENTRY_PID" 2>/dev/null; do
    if wget -q -O /dev/null -T 10 "http://127.0.0.1:${port}/"; then
      fails=0
    else
      fails=$((fails + 1))
      echo "[watchdog] panel did not answer on :${port} (${fails}/${fails_allowed})"
      if [ "$fails" -ge "$fails_allowed" ]; then
        echo "[watchdog] panel is hung, exiting so Docker restarts the container"
        kill -KILL "$ENTRY_PID" 2>/dev/null
        return
      fi
    fi
    sleep "$interval"
  done
}
watchdog &

wait "$ENTRY_PID"
status=$?
echo "[wrapper] entrypoint exited with status ${status}"
exit "$status"
