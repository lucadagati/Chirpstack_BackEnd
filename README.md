# Chirpstack_BackEnd

## Prerequisiti
Prima di procedere con l'installazione e il deployment del container, assicurati di avere installato:
- Docker
- Git (se si intende clonare il repository)

## Installazione
Per installare e avviare il container, segui questi passaggi:

### Clonare il Repository (Opzionale)
Se il progetto è ospitato su un repository GitHub, puoi clonarlo usando:

```bash
git clone https://github.com/lucadagati/Chirpstack_BackEnd.git
cd Chirpstack_BackEnd
```

### Costruire il Container Docker
Per costruire l'immagine Docker, esegui:

```bash
docker build -t chirpstack-complete .
```
Sostituisci `nome-immagine` con il nome che desideri assegnare all'immagine Docker.

### Avviare il Container
Per avviare il container, esegui:

```bash
docker run -dit --restart unless-stopped --name chirpstack chirpstack-complete
```
Sostituisci `nome-container` con il nome che desideri assegnare al tuo container Docker.

## Configurazione
Descrivi qui eventuali passaggi di configurazione necessari, come la configurazione del file `chirpstack-network-server.toml` e `chirpstack-application-server.toml`.

## Uso
Fornisci istruzioni su come utilizzare il container, inclusi eventuali comandi rilevanti.

## Supporto e Contributi
Informazioni su come ottenere supporto e come contribuire al progetto.

## Licenza
Informazioni sulla licenza del progetto.
