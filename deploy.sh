#!/bin/bash

set -e


NOMAD_ADDR="http://127.0.0.1:4646"
JOBS_DIR="/opt/infra/nomad"





systemctl restart consul
systemctl restart nomad
systemctl restart keepalived

echo "=== Waiting for Nomad to be ready ==="

# attendre Nomad

until curl -s $NOMAD_ADDR/v1/status/leader | grep -q ":"; do
echo "Nomad not ready yet..."
sleep 2
done

echo "Nomad is ready"

# vérifier qu'il y a des nodes

echo "=== Checking available nodes ==="
until [ "$(curl -s $NOMAD_ADDR/v1/nodes | jq length)" -gt 0 ]; do
echo "No nodes available yet..."
sleep 2
done

echo "Nodes detected"

echo "=== Deploying jobs ==="

# ordre traefik --> api --> web

nomad job run $JOBS_DIR/traefik.nomad.hcl
sleep 2

nomad job run $JOBS_DIR/api.nomad.hcl
sleep 2

nomad job run $JOBS_DIR/web.nomad.hcl

echo "=== All jobs submitted ==="

nomad job status
