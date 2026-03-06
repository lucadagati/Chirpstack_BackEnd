#!/bin/bash
# Script per creare in ChirpStack: organizzazione, gateway, applicazione, dispositivi
# in modo che LWN-Simulator (già configurato con gli stessi ID/chiavi) funzioni subito.
#
# Uso:
#   1. Apri http://localhost:8080 e registra un utente (o accedi).
#   2. In ChirpStack: Settings -> API keys -> Add API key (salva il token).
#   3. Esegui: docker exec chirpstack /root/seed_demo.sh "IL_TUO_TOKEN"
#      oppure dall'host: curl -s http://localhost:8080/api/internal/login -H "Content-Type: application/json" -d '{"email":"admin@example.com","password":"admin"}' per ottenere un JWT e usarlo qui.

set -e
CHIRPSTACK_URL="${CHIRPSTACK_URL:-http://127.0.0.1:8080}"
TOKEN="$1"

if [ -z "$TOKEN" ]; then
  echo "Uso: $0 <JWT_OR_API_TOKEN>"
  echo ""
  echo "Per ottenere il token:"
  echo "  1. Vai su ${CHIRPSTACK_URL}"
  echo "  2. Registrati o accedi"
  echo "  3. Settings -> API keys -> Add API key, copia il token"
  echo "  4. Esegui: docker exec chirpstack /root/seed_demo.sh \"TOKEN\""
  exit 1
fi

AUTH_HEADER="Grpc-Metadata-Authorization: Bearer $TOKEN"
API="$CHIRPSTACK_URL/api"

echo "Creazione organizzazione Demo..."
ORG_RESP=$(curl -s -X POST "$API/api.OrganizationService/Create" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"organization":{"name":"demo-org","displayName":"Demo per studenti"}}' 2>/dev/null || true)
if echo "$ORG_RESP" | grep -q "already exists\|id"; then
  echo "  Organizzazione presente o creata."
else
  echo "  Risposta: $ORG_RESP"
fi

# Ottieni ID organizzazione (nome = demo-org)
echo "Recupero ID organizzazione..."
ORG_LIST=$(curl -s -X POST "$API/api.OrganizationService/List" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"limit":100}' 2>/dev/null || true)
ORG_ID=$(echo "$ORG_LIST" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$ORG_ID" ]; then
  ORG_ID=$(echo "$ORG_LIST" | grep -o '"organizations":\[{[^]]*' | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
fi
if [ -z "$ORG_ID" ]; then
  echo "Impossibile ottenere l'ID organizzazione. Controlla il token e che l'utente abbia permessi. Risposta: $ORG_LIST"
  exit 1
fi
echo "  Org ID: $ORG_ID"

# Crea gateway (stesso ID usato in LWN-Simulator: 0102030405060708)
echo "Creazione gateway Demo Gateway (0102030405060708)..."
GW_RESP=$(curl -s -X POST "$API/api.GatewayService/Create" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d "{\"gateway\":{\"gatewayId\":\"0102030405060708\",\"name\":\"Demo Gateway\",\"organizationId\":\"$ORG_ID\",\"description\":\"Gateway virtuale per LWN-Simulator\"}}" 2>/dev/null || true)
if echo "$GW_RESP" | grep -q "already exists\|gatewayId"; then
  echo "  Gateway presente o creato."
else
  echo "  Risposta: $GW_RESP"
fi

# Crea device profile
echo "Creazione device profile..."
DP_RESP=$(curl -s -X POST "$API/api.DeviceProfileService/Create" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d "{\"deviceProfile\":{\"name\":\"Demo Profile\",\"organizationId\":\"$ORG_ID\",\"macVersion\":\"1.0.3\",\"regParamsRevision\":\"A\",\"supportsOtaa\":true,\"region\":\"EU868\"}}" 2>/dev/null || true)
DP_ID=$(echo "$DP_RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$DP_ID" ]; then
  DP_LIST=$(curl -s -X POST "$API/api.DeviceProfileService/List" -H "Content-Type: application/json" -H "$AUTH_HEADER" -d "{\"limit\":100,\"organizationId\":\"$ORG_ID\"}" 2>/dev/null || true)
  DP_ID=$(echo "$DP_LIST" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
fi
echo "  Device profile ID: $DP_ID"

# Crea applicazione
echo "Creazione applicazione Demo App..."
APP_RESP=$(curl -s -X POST "$API/api.ApplicationService/Create" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d "{\"application\":{\"name\":\"demo-app\",\"organizationId\":\"$ORG_ID\",\"description\":\"Applicazione demo per LWN-Simulator\"}}" 2>/dev/null || true)
APP_ID=$(echo "$APP_RESP" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -z "$APP_ID" ]; then
  APP_LIST=$(curl -s -X POST "$API/api.ApplicationService/List" -H "Content-Type: application/json" -H "$AUTH_HEADER" -d "{\"limit\":100,\"organizationId\":\"$ORG_ID\"}" 2>/dev/null || true)
  APP_ID=$(echo "$APP_LIST" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
fi
echo "  Application ID: $APP_ID"

# Crea dispositivi OTAA (stessi DevEUI e AppKey di lwnsimulator_demo/devices.json)
echo "Creazione dispositivo Sensore Temperatura (0102030405060709)..."
curl -s -X POST "$API/api.DeviceService/Create" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d "{\"device\":{\"devEui\":\"0102030405060709\",\"name\":\"Sensore Temperatura\",\"applicationId\":\"$APP_ID\",\"deviceProfileId\":\"$DP_ID\",\"description\":\"Demo\"}}" 2>/dev/null || true
echo "Creazione chiave OTAA per 0102030405060709 (AppKey per LoRaWAN 1.0)..."
curl -s -X POST "$API/api.DeviceService/CreateKeys" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"deviceKeys":{"devEui":"0102030405060709","nwkKey":"2b7e151628aed2a6abf7158809cf4f3c"}}' 2>/dev/null || true

echo "Creazione dispositivo Sensore Umidità (0a0b0c0d0e0f1011)..."
curl -s -X POST "$API/api.DeviceService/Create" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d "{\"device\":{\"devEui\":\"0a0b0c0d0e0f1011\",\"name\":\"Sensore Umidità\",\"applicationId\":\"$APP_ID\",\"deviceProfileId\":\"$DP_ID\",\"description\":\"Demo\"}}" 2>/dev/null || true
echo "Creazione chiave OTAA per 0a0b0c0d0e0f1011..."
curl -s -X POST "$API/api.DeviceService/CreateKeys" \
  -H "Content-Type: application/json" \
  -H "$AUTH_HEADER" \
  -d '{"deviceKeys":{"devEui":"0a0b0c0d0e0f1011","nwkKey":"2b7e151628aed2a6abf7158809cf4f3c"}}' 2>/dev/null || true

echo ""
echo "Seed completato. In ChirpStack dovresti vedere:"
echo "  - Organizzazione 'Demo per studenti', gateway 'Demo Gateway', applicazione 'demo-app', 2 dispositivi."
echo "  Apri LWN Simulator su http://localhost:9000, avvia la simulazione e controlla i frame su ChirpStack."
exit 0
