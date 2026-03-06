# ChirpStack Backend

A Docker-based deployment of the **ChirpStack** LoRaWAN network stack with **LWN-Simulator** integration, suitable for teaching and demos. The setup includes ChirpStack Network Server, ChirpStack Application Server, ChirpStack Gateway Bridge, PostgreSQL, Redis, Mosquitto MQTT broker, and LWN-Simulator with pre-configured virtual gateways and OTAA devices.

---

## Table of Contents

- [Overview](#overview)
- [Theory: LoRaWAN and ChirpStack](#theory-lorawan-and-chirpstack)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Student Demo Environment](#student-demo-environment)
- [Usage](#usage)
- [Ports Reference](#ports-reference)
- [Troubleshooting](#troubleshooting)
- [Support and Contributions](#support-and-contributions)

---

## Overview

This repository provides:

- **ChirpStack** (Network Server + Application Server) for managing LoRaWAN gateways, applications, and devices.
- **ChirpStack Gateway Bridge** to accept UDP packet-forwarder traffic (e.g. from LWN-Simulator) and publish to MQTT.
- **LWN-Simulator** with a ready-to-use **ABP** demo: one virtual gateway and two ABP devices (pre-configured) that send uplinks through the ChirpStack Gateway Bridge with no join step.

After a one-time run of the **one-shot script** (with your ChirpStack API token), students open LWN-Simulator, turn on the gateway and devices, and see uplinks in ChirpStack.

---

## Theory: LoRaWAN and ChirpStack

### LoRaWAN in brief

**LoRa** is a proprietary physical layer (PHY) that uses Chirp Spread Spectrum (CSS) in unlicensed sub-GHz bands (e.g. 868 MHz in Europe, 915 MHz in the US). It provides long range and low power at the cost of low data rate and limited payload size.

**LoRaWAN** is the MAC/network layer defined by the LoRa Alliance. It runs on top of LoRa and defines:

- **Star-of-stars topology**: end devices talk only to gateways; gateways forward frames to a central **Network Server** (and optionally a **Join Server**). The Network Server manages device identity, security, and routing of application data to **Application Servers**.
- **Uplink vs downlink**: devices send **uplinks** (device → network); the network can send **downlinks** (network → device) for acknowledgements or commands. Downlinks are constrained by regional regulations (duty cycle, dwell time).
- **Activation**:
  - **OTAA (Over-The-Air Activation)**: device performs a **join** with the network; it uses a root key (AppKey) and receives a **DevAddr** and session keys (NwkSKey, AppSKey). More secure and recommended for production.
  - **ABP (Activation By Personalization)**: DevAddr, NwkSKey, and AppSKey are pre-configured in the device and in the network. No join; the device can send uplinks immediately. Used for testing and demos (as in this project).
- **Identifiers**: each device has a globally unique **DevEUI** (64-bit). After activation it gets a **DevAddr** (32-bit, network-local). **NwkSKey** protects and authenticates MAC commands; **AppSKey** encrypts application payloads.

```mermaid
flowchart LR
    subgraph device["End device"]
        DevEUI[DevEUI]
        DevAddr[DevAddr]
        Keys[NwkSKey / AppSKey]
    end
    subgraph network["Network"]
        GW[Gateway]
        NS[Network Server]
        AS[Application Server]
    end
    DevEUI --> GW
    DevAddr --> GW
    Keys --> GW
    GW --> NS
    NS --> AS
```

### ChirpStack

**ChirpStack** is an open-source LoRaWAN network stack. Its main components are:

| Component | Role |
|-----------|------|
| **ChirpStack Network Server** | Receives uplinks from gateways (via a **Gateway Bridge**), manages device sessions (ABP/OTAA), decrypts and authenticates frames, and forwards application payloads to the Application Server. Handles join requests and downlink scheduling. |
| **ChirpStack Application Server** | Web UI and API for managing **organizations**, **gateways**, **applications**, and **devices**. Stores device metadata, integrates with external systems (e.g. MQTT, HTTP), and shows LoRaWAN frames (uplinks/downlinks) per device. |
| **ChirpStack Gateway Bridge** | Sits between gateways and the rest of the stack. Gateways speak the **Semtech packet-forwarder** protocol (UDP). The bridge converts these packets to MQTT (or gRPC) messages consumed by the Network Server. So ChirpStack can work with any gateway that implements the packet-forwarder protocol. |

In this project, **LWN-Simulator** acts as a virtual gateway plus virtual end devices: it generates LoRaWAN-like uplinks and sends them over UDP (packet-forwarder format) to the ChirpStack Gateway Bridge. That way you can try ChirpStack end-to-end without real hardware.

### How it fits together

1. **LWN-Simulator** defines virtual gateways and ABP devices (DevEUI, DevAddr, NwkSKey, AppSKey) in JSON.
2. The **one-shot script** mirrors that configuration into **ChirpStack** (same gateways and devices, with ABP activation).
3. When you turn ON a device in LWN, it sends uplinks to the virtual gateway → **Gateway Bridge** (UDP 1700) → **MQTT** → **Network Server** → **Application Server** → you see the frames in the ChirpStack UI.

---

## Architecture

### System architecture

All services run inside a single Docker container. The diagram below shows the main components and how they connect.

```mermaid
flowchart TB
    subgraph container["Docker container"]
        subgraph storage["Storage"]
            PG[(PostgreSQL)]
            Redis[(Redis)]
        end

        subgraph chirpstack["ChirpStack"]
            NS[ChirpStack Network Server]
            AS[ChirpStack Application Server]
        end

        MQTT[Mosquitto MQTT]
        GWBR[ChirpStack Gateway Bridge]
        LWN[LWN-Simulator]

        NS --> PG
        NS --> Redis
        NS <--> MQTT
        AS --> PG
        AS --> Redis
        AS <--> MQTT
        GWBR <--> MQTT
        LWN -->|UDP 1700| GWBR
    end

    User[User / Students] -->|HTTP 8080| AS
    User -->|HTTP 9000| LWN
```

- **PostgreSQL**: databases for Network Server (`chirpstack_ns`) and Application Server (`chirpstack_as`).
- **Redis**: used by both ChirpStack components for caching and queues.
- **Mosquitto**: MQTT broker; Network Server and Application Server subscribe/publish here; Gateway Bridge publishes gateway events and receives commands.
- **ChirpStack Gateway Bridge**: listens on UDP port 1700 (Semtech packet-forwarder protocol), converts to MQTT messages consumed by the Network Server.
- **LWN-Simulator**: simulates LoRaWAN devices and a virtual gateway that sends UDP to the Gateway Bridge.

### LoRaWAN demo data flow (ABP)

With ABP, devices send data uplinks immediately (no join). The virtual gateway forwards them to the Gateway Bridge → MQTT → ChirpStack Network Server → Application Server → web UI.

```mermaid
sequenceDiagram
    participant Dev as LWN ABP Device
    participant Fwd as LWN Forwarder
    participant Gw as LWN Virtual Gateway
    participant GWBR as Gateway Bridge
    participant MQTT as Mosquitto
    participant NS as ChirpStack Network Server
    participant AS as ChirpStack Application Server
    participant UI as Web UI

    Note over Dev,UI: ABP data uplink (no join)
    Dev->>Fwd: Data uplink (DevAddr, NwkSKey, AppSKey)
    Fwd->>Gw: RXPK
    Gw->>GWBR: UDP (Semtech PF)
    GWBR->>MQTT: Publish gateway/.../event/up
    MQTT->>NS: Uplink frame
    NS->>AS: Decoded payload (session already known)
    AS->>UI: Show in Applications / Frames
```

---

## Prerequisites

- **Docker**: required to build and run the container.
- **Git**: optional; only needed if you clone the repository (you can also download the archive).

---

## Installation

### 1. Clone or download the repository

```bash
git clone https://github.com/lucadagati/Chirpstack_BackEnd.git
cd Chirpstack_BackEnd
```

### 2. Build the Docker image

```bash
docker build -t chirpstack-complete .
```

This creates the image `chirpstack-complete`. You can change the name by adjusting the `-t` value.

### 3. Start the container

Map the required ports so you can access the web UIs and MQTT from the host:

```bash
docker run -dit --restart unless-stopped --name chirpstack \
  -p 8080:8080 \
  -p 1883:1883 \
  -p 9000:9000 \
  chirpstack-complete
```

- **8080**: ChirpStack web interface.
- **1883**: Mosquitto MQTT (use `-p 1884:1883` if 1883 is already in use on the host).
- **9000**: LWN-Simulator web interface.

Replace `chirpstack` with any container name you prefer.

---

## Configuration

The following configuration files are used inside the container; you can rebuild the image with modified copies if needed:

| Component              | Config path (inside container) |
|------------------------|--------------------------------|
| ChirpStack Network Server | `/etc/chirpstack-network-server/chirpstack-network-server.toml` |
| ChirpStack Application Server | `/etc/chirpstack-application-server/chirpstack-application-server.toml` |
| ChirpStack Gateway Bridge | `/etc/chirpstack-gateway-bridge/chirpstack-gateway-bridge.toml` |
| Mosquitto              | `/etc/mosquitto/mosquitto.conf` |
| LWN-Simulator          | `/LWN-Simulator/config.json` and `/LWN-Simulator/lwnsimulator/*.json` |

Edit these according to your network and region (e.g. band EU868 is set in the Network Server config).

---

## Student Demo Environment (ABP)

The demo uses **ABP (Activation By Personalization)** so devices send data immediately (no join). A **one-shot script** configures both ChirpStack and LWN-Simulator; students run it once with their ChirpStack API token.

### What is pre-configured

```mermaid
flowchart LR
    subgraph lwn["LWN-Simulator"]
        GW[Virtual Gateway<br/>ID: 0102030405060708]
        D1[Temperature Sensor<br/>DevEUI 0102...0709 DevAddr 01020304]
        D2[Humidity Sensor<br/>DevEUI 0a0b...1011 DevAddr 05060708]
    end
    BR[Bridge: localhost:1700]
    GW --> BR
    D1 --> GW
    D2 --> GW
```

- **LWN-Simulator**
  - **Bridge address**: `localhost:1700`.
  - **One virtual gateway**: "Demo Gateway", ID `0102030405060708` (pre-configured in `gateways.json`).
  - **Two ABP devices** (pre-configured in `devices.json`): "Temperature Sensor" and "Humidity Sensor", with DevAddr, NwkSKey, AppSKey set; `supportedOtaa: false` so they send without join.
  - **Auto-start**: simulation starts when the container starts (`autoStart: true`).

- **ChirpStack** (after running the one-shot script): same organization, gateway, application, device profile (ABP, EU868), and two devices with matching DevEUI/DevAddr/NwkSKey/AppSKey.

### One-shot setup (run once; students can use the same)

Run the script **once** after the container is up and you have a ChirpStack API token.

```mermaid
flowchart TD
    A[Start container] --> B[Open ChirpStack http://localhost:8080]
    B --> C[Register or log in]
    C --> D[Settings → API keys → Add API key]
    D --> E[Copy the API token]
    E --> F["docker exec chirpstack /root/seed_demo.sh \"TOKEN\""]
    F --> G[Script: ChirpStack org, gateway, app, ABP profile, 2 devices]
    G --> H[Script: activate ABP sessions; add devices to LWN if needed; start LWN]
    H --> I[Open LWN http://localhost:9000, turn ON gateway and devices]
    I --> J[Uplinks appear in ChirpStack]
```

**Steps:**

1. **Start the container** (if not already running):
   ```bash
   docker run -dit --restart unless-stopped --name chirpstack \
     -p 8080:8080 -p 1883:1883 -p 9000:9000 chirpstack-complete
   ```

2. **Open ChirpStack** at **http://localhost:8080**, **register** or log in.

3. **Create an API key**: **Settings** → **API keys** → **Add API key**. Copy the token.

4. **Run the one-shot script** (replace `YOUR_API_TOKEN`):
   ```bash
   docker exec chirpstack /root/seed_demo.sh "YOUR_API_TOKEN"
   ```
   **Optional auto-seed at startup:** if you already have an API token, you can run the container with `-e CHIRPSTACK_API_TOKEN=your_token` so the script runs automatically after ChirpStack and LWN are ready (no need to run step 4 manually).
   The script uses **LWN config as single source of truth**: it reads `lwnsimulator_demo/gateways.json` and `devices.json` and creates in ChirpStack the same gateways and devices (with names, IDs, and ABP keys). So whatever you define in LWN is mirrored into ChirpStack.
   - Creates organization "demo-org", network server, gateway profile, device profile (ABP EU868), service profile, application "demo-app".
   - Creates every gateway from `gateways.json` and every device from `devices.json`, then activates ABP for each device.
   - Starts the LWN simulation if the API is ready.

5. **Open LWN-Simulator** at **http://localhost:9000**. Turn **ON** the gateway "Demo Gateway" and the two devices. Uplinks will appear in ChirpStack under **Applications** → **demo-app** → device → **LoRaWAN frames**.

### Student workflow (using the demo)

```mermaid
flowchart LR
    subgraph chirpstack_ui["ChirpStack http://localhost:8080"]
        GW_UI[Gateways]
        APP_UI[Applications → demo-app]
        FRAMES[LoRaWAN frames]
    end

    subgraph lwn_ui["LWN-Simulator http://localhost:9000"]
        OPEN[Open dashboard]
        TURN_ON[Turn ON gateway and both ABP devices]
        OBSERVE[Observe uplinks in ChirpStack]
    end

    OPEN --> TURN_ON
    TURN_ON --> OBSERVE
    OBSERVE --> GW_UI
    OBSERVE --> APP_UI
    APP_UI --> FRAMES
```

1. **ChirpStack (http://localhost:8080)**  
   - **Gateways**: "Demo Gateway" should show traffic.  
   - **Applications** → **demo-app**: open each device and check **LoRaWAN frames** for uplinks (ABP: no join, data only).

2. **LWN-Simulator (http://localhost:9000)**  
   - Bridge address is already `localhost:1700`.  
   - Simulation may already be running (auto-start). If not, click **Start**.  
   - Turn **ON** the gateway "Demo Gateway" and the two ABP devices (Temperature Sensor, Humidity Sensor).  
   - Devices send periodic uplinks; frames appear in ChirpStack.

3. **MQTT (optional)**  
   ```bash
   mosquitto_sub -h localhost -p 1883 -t 'gateway/#' -v
   ```

---

## Usage

- **ChirpStack web UI**: **http://localhost:8080** — manage organizations, gateways, applications, devices, and view LoRaWAN frames.
- **LWN-Simulator web UI**: **http://localhost:9000** — run the simulation, turn gateways and devices on/off, change payloads.
- **MQTT**: connect to `localhost:1883` (or the host port you mapped) with any MQTT client; anonymous access is allowed by default.
- **Logs**: `docker logs chirpstack` to view container logs.

---

## Ports Reference

| Service              | Container port | Typical host mapping | Description                    |
|----------------------|----------------|----------------------|--------------------------------|
| ChirpStack Web UI    | 8080           | 8080                 | HTTP UI and API                |
| LWN-Simulator        | 9000           | 9000                 | Simulator web interface        |
| Mosquitto MQTT       | 1883           | 1883 or 1884         | MQTT broker                    |
| Gateway Bridge (UDP) | 1700           | not exposed          | Used only by LWN inside container |

---

## Troubleshooting

| Issue | What to check |
|-------|----------------|
| **LWN not reachable on port 9000** | LWN starts with a delay (12 s) and binds to `0.0.0.0:9000`. Ensure `-p 9000:9000` when running the container. **Start LWN manually:** `docker exec -d chirpstack sh -c 'cd /LWN-Simulator && screen -dmS lwn-simulator ./bin/lwnsimulator'` then wait ~5 s and open http://localhost:9000. The image includes a fallback loop that restarts LWN if it stops (rebuild to get it). |
| **"Unable to load info of gateway bridge" (LWN-Simulator)** | The image includes a fix for the bridge API URL (no trailing slash). Rebuild the image: `docker build -t chirpstack-complete .` and run the container again. |
| **ChirpStack is empty (no org, gateway, devices)** | By design, ChirpStack is not pre-seeded. Run the one-shot script once with your API token: `docker exec chirpstack /root/seed_demo.sh "YOUR_TOKEN"`. Alternatively, start the container with `-e CHIRPSTACK_API_TOKEN=your_token` (or a file at `/root/chirpstack_token`) to auto-run the seed after services are up. |
| **LWN: "Socket not connected"** | This message appears when you click **Run** and the **WebSocket** (Socket.IO) from the browser to the LWN server is not connected yet. **Fix:** (1) Refresh the page and wait 5–10 seconds before clicking Run, so Socket.IO can connect. (2) The image includes a frontend patch so Run is allowed even without WebSocket—rebuild the image (`docker build -t chirpstack-complete .`) and restart the container to get it. The ChirpStack Gateway Bridge (UDP 1700) is separate; ensure it is running with `docker exec chirpstack screen -ls` (you should see `gateway-bridge`). |
| **Gateway not visible in ChirpStack** | Ensure the Gateway Bridge is running: `docker exec chirpstack screen -ls` (you should see `gateway-bridge`). In LWN-Simulator, turn the gateway **ON** and ensure bridge address is `127.0.0.1:1700`. |
| **No uplinks (ABP)** | In ChirpStack, open each device → **Activation** and ensure ABP is set with the same DevAddr, NwkSKey, AppSKey as in the one-shot script (see script or README). Run the one-shot script again or activate once manually. |
| **Simulation does not start** | Check logs: `docker logs chirpstack`. If you prefer to start the simulation manually from the LWN UI, set `autoStart: false` in `config.json` in the Dockerfile and rebuild the image. |
| **Port 1883 already in use** | Use `-p 1884:1883` when running the container and connect MQTT clients to port 1884 on the host. |

---

## Support and Contributions

If you encounter issues or have suggestions, please open an issue or pull request on GitHub. For community support, see the project’s communication channels.
