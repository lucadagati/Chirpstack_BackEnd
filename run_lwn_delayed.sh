#!/bin/bash
# Wrapper per LWN: attende che Gateway Bridge e MQTT siano su, poi avvia il loop run_lwn.sh
sleep 10
exec /root/run_lwn.sh
