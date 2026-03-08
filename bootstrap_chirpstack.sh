#!/bin/bash
# Bootstrap ChirpStack: crea utente demo (se assente), ottiene JWT con login API, esegue seed.
# Uso: nessun token necessario; accedi con demo@local / demo (o CHIRPSTACK_DEMO_EMAIL / CHIRPSTACK_DEMO_PASSWORD).
set -e
CHIRPSTACK_URL="${CHIRPSTACK_URL:-http://127.0.0.1:8080}"
export CHIRPSTACK_DEMO_EMAIL="${CHIRPSTACK_DEMO_EMAIL:-demo@local}"
export CHIRPSTACK_DEMO_PASSWORD="${CHIRPSTACK_DEMO_PASSWORD:-demo}"

echo "=== ChirpStack bootstrap (utente demo + seed) ==="

for i in $(seq 1 30); do
  curl -s -o /dev/null "$CHIRPSTACK_URL/" && break
  sleep 2
done
curl -s -o /dev/null "$CHIRPSTACK_URL/" || { echo "ChirpStack non raggiungibile."; exit 1; }

# Python: genera hash, scrive SQL per INSERT (evita escaping $ nell'hash), poi login
TMP_SQL=$(mktemp)
python3 - "$CHIRPSTACK_URL" "$TMP_SQL" << 'PYBOOT'
import hashlib, base64, os, sys

url = sys.argv[1]
tmp_sql = sys.argv[2]
email = os.environ.get("CHIRPSTACK_DEMO_EMAIL", "demo@local")
password = os.environ.get("CHIRPSTACK_DEMO_PASSWORD", "demo")

iterations = 1
salt = os.urandom(16)
key = hashlib.pbkdf2_hmac("sha512", password.encode(), salt, iterations)
password_hash = "PBKDF2$sha512$%d$%s$%s" % (iterations, base64.b64encode(salt).decode(), base64.b64encode(key).decode())
# Escape per SQL: ' -> ''
hash_esc = password_hash.replace("'", "''")
with open(tmp_sql, "w") as f:
    f.write("-- Upsert utente demo (insert o update hash se esiste)\n")
    f.write("INSERT INTO \"user\" (created_at, updated_at, email, password_hash, session_ttl, is_active, is_admin, email_old, note, email_verified)\n")
    f.write("SELECT NOW(), NOW(), '%s', '%s', 0, true, true, '', '', true\n" % (email.replace("'", "''"), hash_esc))
    f.write("WHERE NOT EXISTS (SELECT 1 FROM \"user\" WHERE email = '%s');\n" % email.replace("'", "''"))
    f.write("UPDATE \"user\" SET password_hash = '%s', updated_at = NOW() WHERE email = '%s';\n" % (hash_esc, email.replace("'", "''")))
PYBOOT

PGPASSWORD=dbpassword psql -h localhost -U chirpstack_as -d chirpstack_as -f "$TMP_SQL" 2>/dev/null || true
rm -f "$TMP_SQL"

# Login e seed
JWT=$(python3 - "$CHIRPSTACK_URL" /root/seed_demo.sh << 'PYLOGIN'
import os, sys, subprocess, urllib.request, json

url = sys.argv[1]
seed_script = sys.argv[2]
email = os.environ.get("CHIRPSTACK_DEMO_EMAIL", "demo@local")
password = os.environ.get("CHIRPSTACK_DEMO_PASSWORD", "demo")

# Login
req = urllib.request.Request(url + "/api/internal/login", data=json.dumps({"email": email, "password": password}).encode(), headers={"Content-Type": "application/json"}, method="POST")
try:
    r = urllib.request.urlopen(req, timeout=10)
    data = json.loads(r.read().decode())
    jwt = data.get("jwt")
    if jwt:
        subprocess.run([seed_script, jwt], check=False)
        print(jwt)
except Exception as e:
    print("Login failed:", e, file=sys.stderr)
    sys.exit(1)
PYLOGIN
)

if [ -z "$JWT" ]; then
  echo "Bootstrap fallito (login senza JWT)."
  exit 1
fi

# Fallback: se l'API non ha creato device (es. errore), creali nel DB
# (normalmente il seed li crea via API con snake_case + activate con camelCase e chiavi hex)
COUNT=$(PGPASSWORD=dbpassword psql -h localhost -U chirpstack_as -d chirpstack_as -t -A -c "SELECT count(*) FROM device WHERE application_id = (SELECT id FROM application WHERE name = 'demo-app' LIMIT 1);" 2>/dev/null)
[ "${COUNT:-0}" = "0" ] && [ -x /root/seed_devices_db.sh ] && /root/seed_devices_db.sh || true

# Associa utenti a demo-org, abilita gateways, metti demo-org prima nella lista (rinomina org vuota)
DEMO_EMAIL_SQL="${CHIRPSTACK_DEMO_EMAIL//\'/\'\'}"
PGPASSWORD=dbpassword psql -h localhost -U chirpstack_as -d chirpstack_as -t -c "
INSERT INTO organization_user (created_at, updated_at, user_id, organization_id, is_admin, is_device_admin, is_gateway_admin)
SELECT NOW(), NOW(), u.id, o.id, true, true, true
FROM \"user\" u, organization o
WHERE u.email = '$DEMO_EMAIL_SQL' AND o.name = 'demo-org'
  AND NOT EXISTS (SELECT 1 FROM organization_user ou WHERE ou.user_id = u.id AND ou.organization_id = o.id);
INSERT INTO organization_user (created_at, updated_at, user_id, organization_id, is_admin, is_device_admin, is_gateway_admin)
SELECT NOW(), NOW(), 1, o.id, true, true, true FROM organization o WHERE o.name = 'demo-org'
  AND NOT EXISTS (SELECT 1 FROM organization_user ou WHERE ou.user_id = 1 AND ou.organization_id = o.id);
UPDATE organization SET can_have_gateways = true WHERE name = 'demo-org';
UPDATE organization SET name = 'z-chirpstack', display_name = 'ChirpStack (empty)' WHERE id = 1 AND name = 'chirpstack';
" 2>/dev/null || true

echo "=== Bootstrap completato. Accedi a ChirpStack con: $CHIRPSTACK_DEMO_EMAIL / $CHIRPSTACK_DEMO_PASSWORD ==="
