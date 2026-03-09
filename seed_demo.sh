#!/bin/bash
# Seed ChirpStack from LWN-Simulator config: creates in ChirpStack every gateway and
# every device defined in lwnsimulator_demo/ (gateways.json, devices.json).
# Single source of truth: LWN config.
#
# Usage:
#   1. Open http://localhost:8080, register, create API key.
#   2. Run: docker exec chirpstack /root/seed_demo.sh "YOUR_TOKEN"

set -e
CHIRPSTACK_URL="${CHIRPSTACK_URL:-http://127.0.0.1:8080}"
LWN_URL="${LWN_URL:-http://127.0.0.1:9000}"
TOKEN="$1"
LWN_CONFIG_DIR="${LWN_CONFIG_DIR:-/LWN-Simulator/lwnsimulator}"

if [ -z "$TOKEN" ]; then
  echo "Usage: $0 <CHIRPSTACK_API_TOKEN>"
  echo "Get the token: ChirpStack -> Settings -> API keys -> Add API key"
  exit 1
fi

AUTH_HEADER="Grpc-Metadata-Authorization: Bearer $TOKEN"
API="$CHIRPSTACK_URL/api"
GW_JSON="$LWN_CONFIG_DIR/gateways.json"
DEV_JSON="$LWN_CONFIG_DIR/devices.json"

get_id() { echo "$1" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4; }

# --- ChirpStack base setup (org, network server, profiles, application) ---
echo "=== ChirpStack (seeded from LWN config) ==="
echo "Organization and network server..."
ORG_CREATE=$(curl -s -X POST "$API/organizations" \
  -H "Content-Type: application/json" -H "$AUTH_HEADER" \
  -d '{"organization":{"name":"demo-org","displayName":"Demo (LWN)","canHaveGateways":true}}')
ORG_ID=$(get_id "$ORG_CREATE")
if [ -z "$ORG_ID" ]; then
  ORG_LIST=$(curl -s -X GET "$API/organizations?limit=100" -H "$AUTH_HEADER")
  ORG_ID=$(echo "$ORG_LIST" | python3 -c "import json,sys; d=json.load(sys.stdin); o=next((x for x in d.get('result',[]) if x.get('name')=='demo-org'), None); print(o['id'] if o else '')" 2>/dev/null)
  [ -z "$ORG_ID" ] && ORG_ID=$(get_id "$ORG_LIST")
fi
[ -z "$ORG_ID" ] && { echo "Could not get organization ID."; exit 1; }
echo "  Org ID: $ORG_ID"

NS_LIST=$(curl -s -X GET "$API/network-servers?limit=10" -H "$AUTH_HEADER")
NS_ID=$(get_id "$NS_LIST")
if [ -z "$NS_ID" ]; then
  NS_CREATE=$(curl -s -X POST "$API/network-servers" \
    -H "Content-Type: application/json" -H "$AUTH_HEADER" \
    -d '{"networkServer":{"name":"Local Network Server","server":"localhost:8000"}}')
  NS_ID=$(get_id "$NS_CREATE")
fi
[ -z "$NS_ID" ] && { echo "No network server."; exit 1; }
echo "  Network server ID: $NS_ID"

echo "Gateway profile (EU868 channels 0,1,2)..."
GP_RESP=$(curl -s -X POST "$API/gateway-profiles" \
  -H "Content-Type: application/json" -H "$AUTH_HEADER" \
  -d "{\"gatewayProfile\":{\"name\":\"Demo Gateway Profile\",\"networkServerID\":\"$NS_ID\",\"channels\":[0,1,2]}}")
GP_ID=$(get_id "$GP_RESP")
[ -z "$GP_ID" ] && GP_ID=$(get_id "$(curl -s -X GET "$API/gateway-profiles?limit=100" -H "$AUTH_HEADER")")
[ -z "$GP_ID" ] && echo "  Warning: gateway profile not created (check API response: $GP_RESP)" || echo "  Gateway profile ID: $GP_ID"

echo "Device profile (ABP, EU868)..."
DP_RESP=$(curl -s -X POST "$API/device-profiles" \
  -H "Content-Type: application/json" -H "$AUTH_HEADER" \
  -d "{\"deviceProfile\":{\"name\":\"Demo ABP Profile\",\"organizationID\":\"$ORG_ID\",\"networkServerID\":\"$NS_ID\",\"macVersion\":\"1.0.3\",\"regParamsRevision\":\"A\",\"supportsJoin\":false,\"rfRegion\":\"EU868\"}}")
DP_ID=$(get_id "$DP_RESP")
[ -z "$DP_ID" ] && DP_ID=$(get_id "$(curl -s -X GET "$API/device-profiles?limit=100&organizationID=$ORG_ID" -H "$AUTH_HEADER")")
echo "  Device profile ID: $DP_ID"

echo "Service profile..."
SP_RESP=$(curl -s -X POST "$API/service-profiles" \
  -H "Content-Type: application/json" -H "$AUTH_HEADER" \
  -d "{\"serviceProfile\":{\"name\":\"demo-service-profile\",\"organizationID\":\"$ORG_ID\",\"networkServerID\":\"$NS_ID\"}}")
SP_ID=$(get_id "$SP_RESP")
[ -z "$SP_ID" ] && SP_ID=$(get_id "$(curl -s -X GET "$API/service-profiles?limit=100&organizationID=$ORG_ID" -H "$AUTH_HEADER")")

echo "Application..."
APP_RESP=$(curl -s -X POST "$API/applications" \
  -H "Content-Type: application/json" -H "$AUTH_HEADER" \
  -d "{\"application\":{\"name\":\"demo-app\",\"organizationID\":\"$ORG_ID\",\"serviceProfileID\":\"$SP_ID\",\"description\":\"Demo app (LWN devices)\"}}")
APP_ID=$(get_id "$APP_RESP")
[ -z "$APP_ID" ] && APP_ID=$(get_id "$(curl -s -X GET "$API/applications?limit=100&organizationID=$ORG_ID" -H "$AUTH_HEADER")")
echo "  Application ID: $APP_ID"

# --- Gateways from LWN gateways.json ---
if [ ! -f "$GW_JSON" ]; then
  echo "Warning: $GW_JSON not found, skipping gateways."
else
  echo "Creating gateways from $GW_JSON..."
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    gw_id=$(echo "$line" | cut -d'|' -f1)
    gw_name=$(echo "$line" | cut -d'|' -f2-)
    [ -z "$gw_id" ] && continue
    gw_name=${gw_name:-"Gateway $gw_id"}
    # ChirpStack gateway name: no spaces (use slug)
    gw_name_slug=$(echo "$gw_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
    [ -z "$gw_name_slug" ] && gw_name_slug="gateway-$gw_id"
    gw_body="{\"gateway\":{\"id\":\"$gw_id\",\"name\":\"$gw_name_slug\",\"organizationID\":\"$ORG_ID\",\"networkServerID\":\"$NS_ID\",\"description\":\"$gw_name\",\"location\":{\"latitude\":38.259987,\"longitude\":15.592595,\"altitude\":0}}}"
    [ -n "$GP_ID" ] && gw_body="{\"gateway\":{\"id\":\"$gw_id\",\"name\":\"$gw_name_slug\",\"organizationID\":\"$ORG_ID\",\"networkServerID\":\"$NS_ID\",\"gatewayProfileID\":\"$GP_ID\",\"description\":\"$gw_name\",\"location\":{\"latitude\":38.259987,\"longitude\":15.592595,\"altitude\":0}}}"
    curl -s -X POST "$API/gateways" -H "Content-Type: application/json" -H "$AUTH_HEADER" -d "$gw_body" >/dev/null 2>&1 || true
    echo "  Gateway: $gw_id ($gw_name)"
  done < <(python3 - "$GW_JSON" << 'PYGW'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    for k, v in data.items():
        if isinstance(v, dict) and "info" in v:
            info = v["info"]
            mac = info.get("macAddress", "").strip().lower().replace(":", "").replace("-", "")
            name = (info.get("name") or "").strip() or ("Gateway " + mac)
            if mac:
                print(mac + "|" + name)
except Exception as e:
    sys.exit(1)
PYGW
)
fi

# --- Devices from LWN devices.json ---
if [ ! -f "$DEV_JSON" ]; then
  echo "Warning: $DEV_JSON not found, skipping devices."
else
  echo "Creating devices and ABP activations from $DEV_JSON..."
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    dev_eui=$(echo "$line" | cut -d'|' -f1)
    dev_name=$(echo "$line" | cut -d'|' -f2)
    dev_addr=$(echo "$line" | cut -d'|' -f3)
    nwk_skey=$(echo "$line" | cut -d'|' -f4)
    app_skey=$(echo "$line" | cut -d'|' -f5)
    [ -z "$dev_eui" ] && continue
    dev_name=${dev_name:-"Device $dev_eui"}
    dev_name_slug=$(echo "$dev_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
    [ -z "$dev_name_slug" ] && dev_name_slug="device-$dev_eui"
    # Create: snake_case; skip_f_cnt_check=true per ABP (evita N/A per frame counter)
    curl -s -X POST "$API/devices" \
      -H "Content-Type: application/json" -H "$AUTH_HEADER" \
      -d "{\"device\":{\"dev_eui\":\"$dev_eui\",\"name\":\"$dev_name_slug\",\"application_id\":$APP_ID,\"device_profile_id\":\"$DP_ID\",\"description\":\"$dev_name\",\"skip_f_cnt_check\":true}}" >/dev/null 2>&1 || true
    # Activate: camelCase (deviceActivation), chiavi in hex; servono anche sNwkSIntKey e fNwkSIntKey (1.0 = stesso valore)
    curl -s -X POST "$API/devices/$dev_eui/activate" \
      -H "Content-Type: application/json" -H "$AUTH_HEADER" \
      -d "{\"deviceActivation\":{\"devEui\":\"$dev_eui\",\"devAddr\":\"$dev_addr\",\"nwkSEncKey\":\"$nwk_skey\",\"appSKey\":\"$app_skey\",\"sNwkSIntKey\":\"$nwk_skey\",\"fNwkSIntKey\":\"$nwk_skey\"}}" >/dev/null 2>&1 || true
    echo "  Device: $dev_eui ($dev_name) ABP $dev_addr"
  done < <(python3 - "$DEV_JSON" << 'PYDEV'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    for k, v in data.items():
        if isinstance(v, dict) and "info" in v:
            info = v["info"]
            eui = (info.get("devEUI") or "").strip().lower().replace(":", "").replace("-", "")
            if len(eui) != 16:
                continue
            name = (info.get("name") or "").strip() or ("Device " + eui)
            addr = (info.get("devAddr") or "").strip().lower().replace(":", "").replace("-", "")
            nwk = (info.get("nwkSKey") or "").strip().lower()
            app = (info.get("appSKey") or "").strip().lower()
            if eui and addr and nwk and app and len(addr) == 8 and len(nwk) == 32 and len(app) == 32:
                print(eui + "|" + name + "|" + addr + "|" + nwk + "|" + app)
except Exception as e:
    sys.exit(1)
PYDEV
)
fi

# --- LWN: ensure simulation can run (devices already in config; start if needed) ---
echo ""
echo "=== LWN-Simulator ==="
for i in 1 2 3 4 5 6 7 8 9 10; do
  curl -s -o /dev/null -w "%{http_code}" "$LWN_URL/api/status" | grep -q 200 && break
  sleep 2
done
if curl -s -o /dev/null -w "%{http_code}" "$LWN_URL/api/status" | grep -q 200; then
  curl -s "$LWN_URL/api/start" >/dev/null || true
  echo "Simulation started (devices and gateway from $LWN_CONFIG_DIR)."
else
  echo "LWN not ready; start it from http://localhost:9000"
fi

echo ""
echo "=== Done ==="
echo "ChirpStack: $CHIRPSTACK_URL — demo-org, demo-app, gateways and devices from LWN config."
echo "LWN: $LWN_URL — turn ON gateways and devices to see uplinks in ChirpStack."
exit 0
