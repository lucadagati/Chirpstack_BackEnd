#!/bin/bash
# Sincronizza i 2 device LWN nel Network Server (device + device_activation) così entrambi ricevono uplink.
# L'API activate aggiorna solo l'AS; il NS ha bisogno di device_activation per decodificare. Idempotente.
# Eseguito dal bootstrap dopo seed_demo.sh.
set -e
export PGPASSWORD="${PGPASSWORD:-dbpassword}"

AS_DB="chirpstack_as"
NS_DB="chirpstack_ns"
NS_KEY="2b7e151628aed2a6abf7158809cf4f3c"

echo "=== Creazione device LWN nel DB (ABP) ==="

# Recupera ID da AS
APP_ID=$(psql -h localhost -U chirpstack_as -d "$AS_DB" -t -A -c "SELECT id FROM application WHERE name = 'demo-app' LIMIT 1;" 2>/dev/null)
DP_AS=$(psql -h localhost -U chirpstack_as -d "$AS_DB" -t -A -c "SELECT device_profile_id FROM device_profile WHERE name = 'Demo ABP Profile' LIMIT 1;" 2>/dev/null)
[ -z "$APP_ID" ] || [ -z "$DP_AS" ] && { echo "  Application o device profile non trovati."; exit 0; }

# Recupera ID da NS
SP_ID=$(psql -h localhost -U chirpstack_ns -d "$NS_DB" -t -A -c "SELECT service_profile_id FROM service_profile LIMIT 1;" 2>/dev/null)
RP_ID=$(psql -h localhost -U chirpstack_ns -d "$NS_DB" -t -A -c "SELECT routing_profile_id FROM routing_profile LIMIT 1;" 2>/dev/null)
[ -z "$SP_ID" ] || [ -z "$RP_ID" ] && { echo "  Service/routing profile NS non trovati."; exit 0; }

# Device 1: Temperature Sensor
# Device 2: Humidity Sensor
psql -h localhost -U chirpstack_as -d "$AS_DB" -c "
INSERT INTO device (dev_eui, created_at, updated_at, application_id, device_profile_id, name, description, dev_addr, app_s_key, device_status_external_power_source)
VALUES 
  (decode('0102030405060709', 'hex'), NOW(), NOW(), $APP_ID, '$DP_AS', 'temperature-sensor', 'Temperature Sensor', decode('01020304', 'hex'), decode('$NS_KEY', 'hex'), false),
  (decode('0a0b0c0d0e0f1011', 'hex'), NOW(), NOW(), $APP_ID, '$DP_AS', 'humidity-sensor', 'Humidity Sensor', decode('05060708', 'hex'), decode('$NS_KEY', 'hex'), false)
ON CONFLICT (dev_eui) DO NOTHING;
" 2>/dev/null || true

psql -h localhost -U chirpstack_ns -d "$NS_DB" -c "
INSERT INTO device (dev_eui, created_at, updated_at, device_profile_id, service_profile_id, routing_profile_id, skip_fcnt_check, reference_altitude, mode, is_disabled)
VALUES 
  (decode('0102030405060709', 'hex'), NOW(), NOW(), '$DP_AS', '$SP_ID', '$RP_ID', true, 0, 'A', false),
  (decode('0a0b0c0d0e0f1011', 'hex'), NOW(), NOW(), '$DP_AS', '$SP_ID', '$RP_ID', true, 0, 'A', false)
ON CONFLICT (dev_eui) DO NOTHING;
" 2>/dev/null || true

psql -h localhost -U chirpstack_ns -d "$NS_DB" -c "
INSERT INTO device_activation (created_at, dev_eui, join_eui, dev_addr, f_nwk_s_int_key, s_nwk_s_int_key, nwk_s_enc_key, dev_nonce, join_req_type)
SELECT NOW(), decode('0102030405060709', 'hex'), decode('0000000000000000', 'hex'), decode('01020304', 'hex'), decode('$NS_KEY', 'hex'), decode('$NS_KEY', 'hex'), decode('$NS_KEY', 'hex'), 0, 0
WHERE NOT EXISTS (SELECT 1 FROM device_activation WHERE dev_eui = decode('0102030405060709', 'hex'));
INSERT INTO device_activation (created_at, dev_eui, join_eui, dev_addr, f_nwk_s_int_key, s_nwk_s_int_key, nwk_s_enc_key, dev_nonce, join_req_type)
SELECT NOW(), decode('0a0b0c0d0e0f1011', 'hex'), decode('0000000000000000', 'hex'), decode('05060708', 'hex'), decode('$NS_KEY', 'hex'), decode('$NS_KEY', 'hex'), decode('$NS_KEY', 'hex'), 0, 0
WHERE NOT EXISTS (SELECT 1 FROM device_activation WHERE dev_eui = decode('0a0b0c0d0e0f1011', 'hex'));
" 2>/dev/null || true

echo "  Device temperature-sensor e humidity-sensor creati in demo-app."
exit 0
