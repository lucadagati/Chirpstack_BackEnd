FROM ubuntu:latest

# Imposta la variabile d'ambiente per non richiedere interazione durante l'installazione
ENV DEBIAN_FRONTEND=noninteractive

# Imposta la time zone
ENV TZ=Europe/Rome
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Crea la directory /run/mosquitto e imposta i permessi
RUN mkdir /run/mosquitto/ && chmod 777 /run/mosquitto/

# Installa le dipendenze
RUN apt-get update && apt-get install -y postgresql mosquitto nano net-tools iputils-ping wget curl software-properties-common build-essential tar ssh git supervisor mosquitto redis-server -y

# Aggiungi la chiave GPG e il repository di ChirpStack
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 1CE2AFD36DBCCA00
RUN echo "deb https://artifacts.chirpstack.io/packages/3.x/deb stable main" | tee /etc/apt/sources.list.d/chirpstack.list
RUN apt-get update

# Installa ChirpStack Network Server, Application Server e Gateway Bridge (per LWN-Simulator)
RUN apt-get install -y chirpstack-network-server chirpstack-application-server chirpstack-gateway-bridge

# Download the Go 1.21.3 tarball
RUN wget https://go.dev/dl/go1.21.3.linux-amd64.tar.gz -O go1.21.3.linux-amd64.tar.gz

# Extract the tarball to /usr/local (installing Go)
RUN tar -C /usr/local -xzf go1.21.3.linux-amd64.tar.gz

# Remove the tarball to clear space
RUN rm go1.21.3.linux-amd64.tar.gz

# Set the Go binary path globally
ENV PATH="/usr/local/go/bin:${PATH}"
#ENV PATH="${PATH}:$(go env GOPATH)/bin"

# Installa statik e aggiorna il PATH
RUN go install github.com/rakyll/statik@latest
ENV PATH="${PATH}:/root/go/bin"

# Usa LWN-Simulator incluso nel repo (nessun clone esterno)
COPY vendor/LWN-Simulator /LWN-Simulator
WORKDIR /LWN-Simulator
# Porta 9000 e bind su tutte le interfacce (raggiungibile da host)
RUN sed -i 's/"port":8000,/"port":9000,/' config.json && \
    sed -i 's/"address":"[^"]*"/"address":"0.0.0.0"/' config.json || true
# Fix: ensure region code 0 (EU868) works when unmarshaling device JSON (nil map entry workaround)
RUN sed -i 's/return r.info()/if r.info == nil { return \&Eu868{} }; return r.info()/' simulator/components/device/regional_parameters/region.go || true
# Fix: frontend calls /api/bridge/ (trailing slash) but server only has /api/bridge - add redirect in Gin or fix JS
RUN sed -i 's|url+"/api/bridge/"|url+"/api/bridge"|g' webserver/public/js/custom/custom.js
# Fix: "Socket not connected" blocks Run — allow start even if Socket.IO not yet connected (real-time updates may be delayed)
RUN sed -i 's/if (!socket.connected){/if (false \&\& !socket.connected){ \/\/ bypass: allow Run without WebSocket/' webserver/public/js/custom/custom.js
RUN make install-dep
# Force statik to be regenerated so embedded FS has index.html (path relative to webserver/public)
RUN rm -rf webserver/statik && make build

# Copia i file di configurazione
COPY chirpstack-network-server.toml /etc/chirpstack-network-server/
COPY chirpstack-application-server.toml /etc/chirpstack-application-server/
COPY setup_postgresql.sh /root/
COPY entrypoint.sh /root/
COPY mosquitto.conf /etc/mosquitto/
RUN mkdir -p /etc/chirpstack-gateway-bridge
COPY chirpstack-gateway-bridge.toml /etc/chirpstack-gateway-bridge/
COPY lwnsimulator_demo/ /LWN-Simulator/lwnsimulator/
COPY seed_demo.sh /root/
COPY seed_devices_db.sh /root/
COPY bootstrap_chirpstack.sh /root/
COPY run_lwn.sh /root/
COPY run_lwn_delayed.sh /root/
RUN chmod +x /root/seed_demo.sh /root/seed_devices_db.sh /root/bootstrap_chirpstack.sh /root/run_lwn.sh /root/run_lwn_delayed.sh
# Supervisord: gestione persistente di tutti i servizi (no screen)
RUN mkdir -p /var/log/supervisor
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY supervisor-chirpstack.conf /etc/supervisor/conf.d/chirpstack.conf

# Abilita avvio automatico della simulazione LWN
RUN sed -i 's/"autoStart": false/"autoStart": true/' /LWN-Simulator/config.json
# Assicura che config sia in bin/ per run-release
RUN cp /LWN-Simulator/config.json /LWN-Simulator/bin/config.json 2>/dev/null || true

# Esegui lo script di configurazione PostgreSQL
RUN chmod +x /root/setup_postgresql.sh && /root/setup_postgresql.sh

# Imposta lo script di avvio
RUN chmod +x /root/entrypoint.sh
ENTRYPOINT ["/root/entrypoint.sh"]
