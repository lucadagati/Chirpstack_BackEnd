#!/bin/bash
# Avvia LWN-Simulator in loop: se il processo termina, riavvio dopo 5 secondi.
# Eseguito in background dall'entrypoint così la porta 9000 resta attiva.
cd /LWN-Simulator || exit 1
while true; do
  [ -x ./bin/lwnsimulator ] && ./bin/lwnsimulator
  sleep 5
done
