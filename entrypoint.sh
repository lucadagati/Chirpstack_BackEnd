#!/bin/bash
# Avvio: PostgreSQL, Redis, (optional seed in background), poi supervisord come PID 1.
# Supervisord gestisce in modo persistente: mosquitto, ChirpStack NS/AS, Gateway Bridge, LWN.

# PostgreSQL e DB ChirpStack
service postgresql start
sleep 3
/root/setup_postgresql.sh 2>/dev/null || true

# Redis
service redis-server start
sleep 2

# Auto-seed ChirpStack (in background): con token fornito, oppure bootstrap (crea utente demo + login API + seed)
(
  TOKEN="${CHIRPSTACK_API_TOKEN:-}"
  [ -z "$TOKEN" ] && [ -f /root/chirpstack_token ] && TOKEN="$(cat /root/chirpstack_token)"
  echo "Waiting for ChirpStack (8080)..."
  for i in $(seq 1 45); do curl -s -o /dev/null http://127.0.0.1:8080/ && break; sleep 2; done
  sleep 5
  if [ -n "$TOKEN" ]; then
    /root/seed_demo.sh "$TOKEN" && echo "Auto-seed completed (token)." || true
  else
    /root/bootstrap_chirpstack.sh && echo "Bootstrap (utente demo + seed) completed." || true
  fi
) &

# Supervisord come processo principale (gestisce mosquitto, ChirpStack, LWN; restart automatico)
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
