# ============================================================
# README - Déploiement Consul + Nomad
# Application de redimensionnement d'images
# ============================================================

## Architecture des VMs

Pour un cluster minimal en prod :

  VM 1 (10.0.1.1) : consul-server + nomad-server
  VM 2 (10.0.1.2) : consul-server + nomad-server
  VM 3 (10.0.1.3) : consul-server + nomad-server + nomad-client (storage)
  VM 4 (10.0.1.4) : consul-client + nomad-client (workloads)
  VM 5 (10.0.1.5) : consul-client + nomad-client (workloads)

Les jobs Redis et MinIO tournent sur VM3 (storage).
Les jobs api/worker/web tournent sur VM4 et VM5.


## Étape 1 : Installer Consul et Nomad sur chaque VM

  # Sur Ubuntu/Debian :
  wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor \
    | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg

  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list

  sudo apt update && sudo apt install consul nomad


## Étape 2 : Générer la clé de chiffrement Consul

  consul keygen
  # Copier la valeur dans tous les fichiers consul-*.hcl (champ "encrypt")


## Étape 3 : Copier les configs et démarrer

  # Sur les VMs server :
  sudo cp consul-server.hcl /etc/consul.d/consul.hcl
  sudo cp nomad-server.hcl  /etc/nomad.d/nomad.hcl

  # Sur les VMs client :
  sudo cp consul-client.hcl /etc/consul.d/consul.hcl
  sudo cp nomad-client.hcl  /etc/nomad.d/nomad.hcl

  # Démarrer les services (systemd)
  sudo systemctl enable --now consul
  sudo systemctl enable --now nomad


## Étape 4 : Configurer le DNS Consul sur chaque VM

  # Créer /etc/systemd/resolved.conf.d/consul.conf :
  [Resolve]
  DNS=127.0.0.1:8600
  Domains=~consul

  sudo systemctl restart systemd-resolved

  # Tester :
  dig @127.0.0.1 -p 8600 consul.service.consul


## Étape 5 : Builder et pusher les images Docker

  docker build -t tonusername/image-api:latest ./api
  docker push tonusername/image-api:latest

  docker build -t tonusername/image-web:latest ./web
  docker push tonusername/image-web:latest


## Étape 6 : Créer le dossier de données MinIO sur VM3

  sudo mkdir -p /opt/minio-data
  sudo chown -R nobody:nobody /opt/minio-data


## Étape 7 : Déployer les jobs Nomad (dans l'ordre)

  # D'abord les services d'infrastructure
  nomad job run jobs/redis.nomad.hcl
  nomad job run jobs/minio.nomad.hcl

  # Attendre qu'ils soient healthy dans Consul :
  watch consul catalog services

  # Puis les services applicatifs
  nomad job run jobs/api.nomad.hcl
  nomad job run jobs/web.nomad.hcl


## Commandes utiles

  # État du cluster Nomad
  nomad node status
  nomad job status image-api

  # Logs d'un job
  nomad alloc logs <alloc-id>

  # État des services dans Consul
  consul catalog services
  consul health service redis

  # Résolution DNS (test)
  dig redis.service.consul
  dig minio.service.consul


## Différences clés avec Docker Compose

  Docker Compose               Nomad + Consul
  ─────────────────────────    ─────────────────────────────────
  depends_on                → Retry dans l'application + health checks Consul
  Noms DNS (redis, minio)   → redis.service.consul, minio.service.consul
  volumes: minio_data       → Mount de dossier hôte /opt/minio-data
  ports: "8080:8080"        → network { port "http" { static = 8080 } }
  environment:              → env { } dans la task
  restart: always           → type = "service" (Nomad redémarre automatiquement)
  healthcheck               → check { } dans le bloc service { }
