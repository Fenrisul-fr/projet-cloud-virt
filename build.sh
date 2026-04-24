#!/bin/bash

set -e

ROLE=$1
LEADER_IP="192.168.24.101"
REPO_URL="https://github.com/Fenrisul-fr/projet-cloud-virt"

echo "=== INSTALLATION CONSUL / NOMAD / VAULT ==="

# 1. Install packages

apt update
apt install -y vault nomad consul

# 2. Enable services

systemctl enable vault
systemctl enable nomad
systemctl enable consul

# 3. Pull config repo

cd /opt
if [ ! -d "infra" ]; then
git clone $REPO_URL infra
fi

# 4. Copy configs

cp infra/vault/vault.hcl /etc/vault.d/vault.hcl
cp infra//nomad/nomad.hcl /etc/nomad.d/nomad.hcl
cp infra/consul/consul.hcl /etc/consul.d/consul.hcl

mkdir -p /opt/vault/tls

# =========================

# ===== LEADER SETUP ======

# =========================

if [ "$ROLE" == "leader" ]; then

echo "=== SETUP LEADER (VM1) ==="

# Generate CA

openssl genrsa -out /opt/vault/tls/ca.key 4096
openssl req -x509 -new -nodes -key /opt/vault/tls/ca.key -days 365 -out /opt/vault/tls/ca.crt -subj "/CN=vault-ca"

echo "=== START VAULT ==="
systemctl restart vault

echo ""
echo "=== ACTION MANUELLE REQUISE ==="
echo "1. Lance : vault operator init"
echo "2. Sauvegarde les clés"
echo "3. Fais le unseal"
echo ""
read -p "Appuie sur ENTER une fois Vault unsealed..."

# Vérifier que Vault est prêt

export VAULT_ADDR="https://$(hostname -I | awk '{print $1}'):8200"
export VAULT_SKIP_VERIFY=true

echo "=== Vérification Vault ==="
until vault status | grep -q "Sealed.*false"; do
echo "Vault non prêt ou encore sealed..."
sleep 2
done

echo "Vault est prêt"

# =========================

# ===== SAISIE SECRETS ====

# =========================

echo ""
echo "=== SAISIE DES SECRETS IMAGE-API ==="

read -p "AWS ACCESS KEY: " AWS_ACCESS_KEY
read -s -p "AWS SECRET KEY: " AWS_SECRET_KEY
echo ""
read -p "BROKER URL: " BROKER_URL
read -p "BUCKET NAME: " BUCKET_NAME

# =========================

# ===== CONFIG VAULT ======

# =========================

echo "=== Configuration Vault ==="

vault secrets enable -path=secret kv-v2 || true

vault kv put secret/image-api aws_access_key_id="$AWS_ACCESS_KEY" aws_secret_access_key="$AWS_SECRET_KEY" broker_url="$BROKER_URL" bucket_name="$BUCKET_NAME"

echo "=== Policy image-api ==="

vault policy write image-api - <<EOF
path "secret/data/image-api" {
capabilities = ["read"]
}
EOF

echo "=== Activation JWT ==="

vault auth enable jwt || true

vault write auth/jwt/config 
jwks_url="http://192.168.24.101:4646/.well-known/jwks.json" 
jwt_supported_algs="RS256,EdDSA"

echo "=== Création rôle JWT image-api ==="

vault write auth/jwt/role/image-api-role role_type="jwt" bound_audiences="vault.io" user_claim="/nomad_job_id" user_claim_json_pointer=true bound_claims.nomad_job_id="image-api" token_policies="image-api" token_period="30m"

echo ""
echo "=== IMPORTANT ==="
echo "1. Copie /opt/vault/tls/ca.crt et /opt/vault/tls/ca.key sur les autres VMs"
echo "2. Lance le script sur les autres VMs en mode worker"

fi



# =========================

# ===== WORKER SETUP ======

# =========================

if [ "$ROLE" == "worker" ]; then

echo "=== SETUP WORKER ==="

# CA normalement récup 

echo "=== Génération certificat signé ==="

openssl genrsa -out /opt/vault/tls/tls.key 4096

openssl req -new -key /opt/vault/tls/tls.key -out /tmp/vm.csr -subj "/CN=vault-worker" 

openssl x509 -req -in /tmp/vm.csr -CA /opt/vault/tls/ca.crt -CAkey /opt/vault/tls/ca.key -CAcreateserial -out /opt/vault/tls/tls.crt -days 365 -extfile <(echo "subjectAltName=IP:192.168.24.103,IP:127.0.0.1")

chown vault:vault /opt/vault/tls/*

systemctl restart vault

echo "=== JOIN CLUSTER ==="
export VAULT_ADDR="https://$(hostname -I | awk '{print $1}'):8200"
export VAULT_CACERT="/opt/vault/tls/ca.crt"

vault operator raft join -leader-ca-cert=@/opt/vault/tls/ca.crt https://$LEADER_IP:8200

echo "=== IMPORTANT ==="
echo "Fais le unseal avec les clés du leader"

fi

echo "=== DONE ==="
