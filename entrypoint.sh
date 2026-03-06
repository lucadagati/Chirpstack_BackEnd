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
sleep 2

# Avvia ChirpStack Gateway Bridge (UDP 1700 -> MQTT, per LWN-Simulator)
screen -dmS gateway-bridge chirpstack-gateway-bridge -c /etc/chirpstack-gateway-bridge/chirpstack-gateway-bridge.toml

# Esegui 'make run' nella cartella LWN-Simulator in una schermata screen
cd /LWN-Simulator
screen -dmS lwn-simulator make run

# Mantieni il container in esecuzione
tail -f /dev/null

