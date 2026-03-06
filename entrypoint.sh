#!/bin/bash

# Avvia PostgreSQL
service postgresql start

#Avvia Redis
service redis-server start

# Avvia il ChirpStack Network Server in una schermata screen
screen -dmS network-server chirpstack-network-server

# Avvia il ChirpStack Application Server in una schermata screen
screen -dmS application-server chirpstack-application-server

# Avvia Mqtt
screen -dmS mqtt mosquitto -c /etc/mosquitto/mosquitto.conf

# Attendi che MQTT sia pronto prima di avviare il Gateway Bridge
sleep 5

# Avvia ChirpStack Gateway Bridge (UDP 1700 -> MQTT); LWN si connette qui
screen -dmS gateway-bridge chirpstack-gateway-bridge -c /etc/chirpstack-gateway-bridge/chirpstack-gateway-bridge.toml
sleep 3

# LWN-Simulator: avvio dopo che il bridge è in ascolto su 1700 (bridgeAddress in lwnsimulator/simulator.json)
(sleep 8; screen -dmS lwn-simulator sh -c 'cd /LWN-Simulator && (test -x bin/lwnsimulator && exec ./bin/lwnsimulator || exec make run)') &

# Optional: auto-run seed if token is provided (env CHIRPSTACK_API_TOKEN or file /root/chirpstack_token)
(
  TOKEN="${CHIRPSTACK_API_TOKEN:-}"
  [ -z "$TOKEN" ] && [ -f /root/chirpstack_token ] && TOKEN="$(cat /root/chirpstack_token)"
  if [ -n "$TOKEN" ]; then
    echo "Waiting for ChirpStack and LWN-Simulator to be ready for auto-seed..."
    for i in $(seq 1 30); do
      curl -s -o /dev/null http://127.0.0.1:8080/ && curl -s -o /dev/null http://127.0.0.1:9000/api/status && break
      sleep 2
    done
    sleep 5
    /root/seed_demo.sh "$TOKEN" && echo "Auto-seed completed." || true
  fi
) &

# Mantieni il container in esecuzione
tail -f /dev/null

