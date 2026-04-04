#!/usr/bin/env bash
# ============================================================
# build-and-deploy.sh
#
# Clone un dépôt Git, build les images Docker localement,
# puis déploie les jobs Nomad.
#
# Usage :
#   ./build-and-deploy.sh [--branch main] [--skip-build]
#
# Prérequis sur la VM :
#   - git, docker, nomad installés
#   - L'utilisateur courant dans le groupe "docker"
#     (sudo usermod -aG docker $USER)
# ============================================================

set -euo pipefail
# set -e : quitte immédiatement si une commande échoue
# set -u : erreur si une variable non définie est utilisée
# set -o pipefail : un pipe échoue si l'une de ses commandes échoue

# -------------------------------------------------------
# Configuration — adapter à ton projet
# -------------------------------------------------------
GIT_REPO="https://github.com/Fenrisul-fr/projet-cloud-virt"
GIT_BRANCH="main"
BUILD_DIR="/opt/app-build"          # Dossier de travail sur la VM
API_IMAGE="image-api"               # Nom de l'image locale pour l'API/worker
WEB_IMAGE="image-web"               # Nom de l'image locale pour le frontend
NOMAD_JOBS_DIR="/etc/nomad.d/jobs"  # Dossier des jobs .hcl

SKIP_BUILD=false

# -------------------------------------------------------
# Parsing des arguments
# -------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --branch)
      GIT_BRANCH="$2"
      shift 2
      ;;
    --skip-build)
      # Utile si tu veux juste re-déployer sans rebuilder
      SKIP_BUILD=true
      shift
      ;;
    *)
      echo "Argument inconnu : $1"
      exit 1
      ;;
  esac
done

# -------------------------------------------------------
# Fonctions utilitaires
# -------------------------------------------------------
log() { echo "[$(date '+%H:%M:%S')] $*"; }
die() { echo "[ERREUR] $*" >&2; exit 1; }

# -------------------------------------------------------
# Étape 1 : Récupérer le code source
# -------------------------------------------------------
log "=== Étape 1 : Récupération du code source ==="

if [ -d "$BUILD_DIR/.git" ]; then
  # Le repo existe déjà : on met juste à jour
  log "Dépôt existant, mise à jour..."
  cd "$BUILD_DIR"
  git fetch origin
  git checkout "$GIT_BRANCH"
  git pull origin "$GIT_BRANCH"
else
  # Premier clone
  log "Premier clone du dépôt..."
  sudo mkdir -p "$BUILD_DIR"
  sudo chown "$USER:$USER" "$BUILD_DIR"
  git clone --branch "$GIT_BRANCH" "$GIT_REPO" "$BUILD_DIR"
  cd "$BUILD_DIR"
fi

# On récupère le hash court du commit courant.
# On l'utilise comme tag d'image pour savoir quelle version tourne.
# Ex: "image-api:a3f2c1d"
COMMIT_HASH=$(git rev-parse --short HEAD)
log "Commit actuel : $COMMIT_HASH (branche $GIT_BRANCH)"

# -------------------------------------------------------
# Étape 2 : Build des images Docker
# -------------------------------------------------------
if [ "$SKIP_BUILD" = false ]; then
  log "=== Étape 2 : Build des images Docker ==="

  # Build de l'API (et du worker, même image)
  log "Build de $API_IMAGE:$COMMIT_HASH..."
  docker build \
    --tag "$API_IMAGE:$COMMIT_HASH" \
    --tag "$API_IMAGE:latest" \
    --file "$BUILD_DIR/api/Dockerfile" \
    "$BUILD_DIR/api"

  # Build du frontend
  log "Build de $WEB_IMAGE:$COMMIT_HASH..."
  docker build \
    --tag "$WEB_IMAGE:$COMMIT_HASH" \
    --tag "$WEB_IMAGE:latest" \
    --file "$BUILD_DIR/web/Dockerfile" \
    "$BUILD_DIR/web"

  log "Images buildées avec succès :"
  docker images | grep -E "^($API_IMAGE|$WEB_IMAGE)"

  # -------------------------------------------------------
  # Nettoyage des vieilles images
  # Sans ça, les builds s'accumulent et remplissent le disque.
  # On garde les 3 dernières versions de chaque image.
  # -------------------------------------------------------
  log "Nettoyage des vieilles images..."
  docker image prune -f --filter "until=168h"  # Supprime les images > 7 jours
else
  log "=== Étape 2 : Build ignoré (--skip-build) ==="
fi

# -------------------------------------------------------
# Étape 3 : Injecter le tag de commit dans les jobs Nomad
#
# Les fichiers .hcl contiennent un placeholder __IMAGE_TAG__
# qu'on remplace par le hash du commit courant.
# Ça permet à Nomad de détecter que l'image a changé et
# de redémarrer les conteneurs.
# -------------------------------------------------------
log "=== Étape 3 : Préparation des jobs Nomad ==="

JOBS_STAGING_DIR="/tmp/nomad-jobs-$COMMIT_HASH"
mkdir -p "$JOBS_STAGING_DIR"

for job_file in "$NOMAD_JOBS_DIR"/*.nomad.hcl; do
  filename=$(basename "$job_file")
  # Remplace le placeholder par le vrai tag
  sed "s/__IMAGE_TAG__/$COMMIT_HASH/g" "$job_file" > "$JOBS_STAGING_DIR/$filename"
  log "  Préparé : $filename (tag: $COMMIT_HASH)"
done

# -------------------------------------------------------
# Étape 4 : Déploiement des jobs Nomad
#
# Ordre important :
#   1. Infrastructure (redis, minio) — doivent être healthy avant l'app
#   2. Services applicatifs (api, web)
# -------------------------------------------------------
log "=== Étape 4 : Déploiement Nomad ==="

deploy_job() {
  local job_file="$1"
  local job_name="$2"
  local wait_healthy="${3:-true}"

  log "Déploiement de $job_name..."
  nomad job run "$job_file"

  if [ "$wait_healthy" = true ]; then
    log "Attente que $job_name soit healthy..."
    # Attend jusqu'à 120 secondes que le job soit "running"
    timeout 120 bash -c "
      until nomad job status $job_name | grep -q 'Status.*running'; do
        sleep 3
      done
    " || die "$job_name n'est pas passé en état 'running' après 120s"

    log "$job_name est running ✓"
  fi
}

# Infrastructure d'abord
deploy_job "$JOBS_STAGING_DIR/redis.nomad.hcl"  "redis"
deploy_job "$JOBS_STAGING_DIR/minio.nomad.hcl"  "minio"

# Attendre que Redis et MinIO soient enregistrés dans Consul
log "Vérification des services dans Consul..."
timeout 60 bash -c "
  until consul catalog services | grep -q 'redis' && \
        consul catalog services | grep -q 'minio'; do
    sleep 2
  done
" || die "Redis ou MinIO non enregistrés dans Consul après 60s"

log "Services d'infrastructure disponibles dans Consul ✓"

# Services applicatifs
deploy_job "$JOBS_STAGING_DIR/api.nomad.hcl" "image-api"
deploy_job "$JOBS_STAGING_DIR/web.nomad.hcl" "web"

# -------------------------------------------------------
# Étape 5 : Vérification finale
# -------------------------------------------------------
log "=== Déploiement terminé ==="
log ""
log "Commit déployé : $COMMIT_HASH"
log ""
log "État des jobs Nomad :"
nomad job status redis
nomad job status minio
nomad job status image-api
nomad job status web
log ""
log "Services Consul :"
consul catalog services

# Nettoyage du dossier temporaire
rm -rf "$JOBS_STAGING_DIR"
