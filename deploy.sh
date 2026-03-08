#!/bin/bash
# Deploy ChirpStack + LWN: build image, run container. Bootstrap (demo user + seed) è automatico all'avvio.
# Uso: ./deploy.sh [--clean]
#   --clean: rimuove container e immagine esistenti prima di buildare.
set -e
IMAGE_NAME="${IMAGE_NAME:-chirpstack-complete}"
CONTAINER_NAME="${CONTAINER_NAME:-chirpstack}"

if [ "$1" = "--clean" ]; then
  echo "=== Clean: stop and remove container and image ==="
  docker stop "$CONTAINER_NAME" 2>/dev/null || true
  docker rm "$CONTAINER_NAME" 2>/dev/null || true
  docker rmi "$IMAGE_NAME" 2>/dev/null || true
fi

echo "=== Build image: $IMAGE_NAME ==="
docker build -t "$IMAGE_NAME" .

echo "=== Run container: $CONTAINER_NAME ==="
docker run -dit --restart unless-stopped --name "$CONTAINER_NAME" \
  -p 8080:8080 \
  -p 1884:1883 \
  -p 9000:9000 \
  "$IMAGE_NAME"

echo ""
echo "Deploy avviato. Attendere ~60 s per bootstrap (utente demo + seed)."
echo "  ChirpStack: http://localhost:8080  (login: demo@local / demo — seleziona org demo-org)"
echo "  LWN-Simulator: http://localhost:9000"
echo "  MQTT: localhost:1884"
echo ""
echo "Verifica: docker exec $CONTAINER_NAME supervisorctl status"
