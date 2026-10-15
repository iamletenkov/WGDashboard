#!/bin/sh
# Mounted into /docker-entrypoint.d/: the stock nginx entrypoint runs it before starting
# nginx (after rendering the templates). It leaves a background loop that reloads nginx
# when the certificate file changes (issue, renewal), so no container needs the Docker socket.
cert="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
(
  last=$(stat -L -c %Y "$cert" 2>/dev/null)
  while sleep 60; do
    now=$(stat -L -c %Y "$cert" 2>/dev/null)
    if [ -n "$now" ] && [ "$now" != "$last" ]; then
      echo "[reload-on-cert-change] certificate changed, reloading nginx"
      nginx -s reload
      last=$now
    fi
  done
) &
