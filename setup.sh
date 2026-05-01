#!/bin/bash
set -euo pipefail

# ============================================================
# setup.sh
# Usage :
#   sudo ./setup.sh leader    → vm1 : installe tout, init Vault, génère CA
#   sudo ./setup.sh worker    → vm2/3 : installe tout, rejoint le cluster
#
# Prérequis worker :
#   Le CA de vm1 doit être disponible via HTTP sur vm1 :
#   cd /opt/vault/tls && python3 -m http.server 9999
#   (arrêter après que toutes les VMs ont récupéré le CA)
# ============================================================

ROLE=${1:-""}
LEADER_IP="192.168.24.101"
REPO_URL="https://github.com/Fenrisul-fr/projet-cloud-virt"

if [ -z "$ROLE" ]; then
  echo "Usage : $0 leader|worker"
  exit 1
fi

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# -------------------------------------------------------
# Détecte l'IP privée de cette VM
# -------------------------------------------------------
VM_IP=$(hostname -I | awk '{print $1}')
VM_IFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
VM_NAME=$(hostname)
log "VM IP détectée : $VM_IP"
log "VM Interface détecté: $VM_IFACE"
log "VM Name : $VM_NAME"

# ============================================================
# ÉTAPE 1 : Installation des packages
# ============================================================
log "=== Étape 1 : Installation Consul / Nomad / Vault ==="

# Ajout du repo HashiCorp si pas déjà présent
if [ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]; then
  wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    tee /etc/apt/sources.list.d/hashicorp.list
fi

apt update -qq
apt install -y vault nomad consul git keepalived

# ============================================================
# ÉTAPE 2 : Récupération du repo
# ============================================================
log "=== Étape 2 : Pull du repo ==="

if [ ! -d /opt/infra ]; then
  git clone "$REPO_URL" /opt/infra
else
  git -C /opt/infra pull
fi

# ============================================================
# ÉTAPE 3 : Copie des configs
# ============================================================
log "=== Étape 3 : Copie des configs ==="

# Consul
cp /opt/infra/consul/consul.hcl /etc/consul.d/consul.hcl
# Injecte l'IP et le nom de la VM dans la config Consul
echo "bind_addr = \"$VM_IP\"" >> /etc/consul.d/consul.hcl

# Nomad
cp /opt/infra/nomad/nomad.hcl /etc/nomad.d/nomad.hcl

# Keepalived config différente selon le rôle
mkdir -p /etc/keepalived
if [ "$ROLE" == "leader" ]; then
  cat > /etc/keepalived/keepalived.conf <<EOF
vrrp_instance ip_virt {
    state MASTER
    interface $VM_IFACE
    virtual_router_id 51
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass pailhe
    }
    virtual_ipaddress {
        192.168.24.110
    }
}
EOF
fi

if [ "$ROLE" == "worker" ]; then
  cat > /etc/keepalived/keepalived.conf <<EOF
vrrp_instance ip_virt {
    state BACKUP
    interface $VM_IFACE
    virtual_router_id 51
    priority 60
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass pailhe
    }
    virtual_ipaddress {
        192.168.24.110
    }
}
EOF

# Vault — config différente selon le rôle
mkdir -p /opt/vault/tls /opt/vault/data

# Génère la config vault.hcl avec l'IP de cette VM
cat > /etc/vault.d/vault.hcl << EOF
ui            = true
disable_mlock = true

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "$VM_NAME"
}

api_addr     = "https://${VM_IP}:8200"
cluster_addr = "https://${VM_IP}:8201"

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_cert_file      = "/opt/vault/tls/tls.crt"
  tls_key_file       = "/opt/vault/tls/tls.key"
  tls_client_ca_file = "/opt/vault/tls/ca.crt"
}
EOF

chown vault:vault /etc/vault.d/vault.hcl

# Active les services au démarrage
systemctl enable consul nomad vault keepalived

# ============================================================
# ÉTAPE 4 : Génération des certificats TLS
# ============================================================
log "=== Étape 4 : Certificats TLS ==="

if [ "$ROLE" == "leader" ]; then
  # Génère le CA sur le leader
  log "Génération du CA sur le leader..."
  openssl genrsa -out /opt/vault/tls/ca.key 4096
  openssl req -x509 -new -nodes \
    -key /opt/vault/tls/ca.key \
    -days 3650 \
    -out /opt/vault/tls/ca.crt \
    -subj "/CN=vault-ca"
  log "CA généré"

else
  # Worker : récupère le CA depuis vm1 via HTTP
  log "Récupération du CA depuis $LEADER_IP..."
  log ""
  log "⚠️  Sur vm1, lance d'abord :"
  log "   cd /opt/vault/tls && python3 -m http.server 9999"
  log ""
  read -p "Appuie sur ENTER une fois le serveur HTTP lancé sur vm1..."

  wget -q "http://${LEADER_IP}:9999/ca.crt" -O /opt/vault/tls/ca.crt
  wget -q "http://${LEADER_IP}:9999/ca.key" -O /opt/vault/tls/ca.key
  log "CA récupéré depuis vm1"
fi

# Génère le certificat de CETTE VM signé par le CA
log "Génération du certificat pour $VM_NAME ($VM_IP)..."
openssl genrsa -out /opt/vault/tls/tls.key 4096
openssl req -new \
  -key /opt/vault/tls/tls.key \
  -out /tmp/${VM_NAME}.csr \
  -subj "/CN=vault-${VM_NAME}"
openssl x509 -req -in /tmp/${VM_NAME}.csr \
  -CA /opt/vault/tls/ca.crt \
  -CAkey /opt/vault/tls/ca.key \
  -CAcreateserial \
  -out /opt/vault/tls/tls.crt \
  -days 365 \
  -extfile <(echo "subjectAltName=IP:${VM_IP},IP:127.0.0.1")

chown vault:vault /opt/vault/tls/tls.key /opt/vault/tls/tls.crt

log "Certificat généré et signé par le CA"

# Vérification
openssl verify -CAfile /opt/vault/tls/ca.crt /opt/vault/tls/tls.crt
log "Certificat validé"

# ============================================================
# ÉTAPE 5 : Démarrage des services
# ============================================================
log "=== Étape 5 : Démarrage des services ==="

systemctl restart consul
sleep 3
systemctl restart nomad
sleep 3

if [ "$ROLE" == "worker" ]; then
  log "Nettoyage du storage Raft..."
  rm -rf /opt/vault/data/*
  mkdir -p /opt/vault/data
  chown -R vault:vault /opt/vault/data
fi

systemctl restart vault
sleep 3


export VAULT_ADDR="https://${VM_IP}:8200"
export VAULT_CACERT="/opt/vault/tls/ca.crt"

# ============================================================
# ÉTAPE 6 : Initialisation Vault (leader uniquement)
# ============================================================
if [ "$ROLE" == "leader" ]; then
  log "=== Étape 6 : Initialisation Vault ==="

  log ""
  log "⚠️  Lance maintenant dans un autre terminal :"
  log "   export VAULT_ADDR=https://${VM_IP}:8200"
  log "   export VAULT_CACERT=/opt/vault/tls/ca.crt"
  log "   vault operator init"
  log "   vault operator unseal  (3 fois)"
  log ""
  read -p "Appuie sur ENTER une fois Vault initialisé et unsealed..."

  # Attend que Vault soit unsealed
  until vault status 2>/dev/null | grep -q "Sealed.*false"; do
    log "Vault encore sealed, attente..."
    sleep 3
  done
  log "Vault unsealed"

  # ============================================================
  # ÉTAPE 7 : Configuration des secrets (leader uniquement)
  # ============================================================
  log "=== Étape 7 : Configuration des secrets ==="
  log ""
  log "Entre le token root obtenu lors du vault operator init :"
  read -s -p "Root token : " ROOT_TOKEN
  echo ""
  export VAULT_TOKEN="$ROOT_TOKEN"

  log ""
  log "=== Saisie des secrets ==="
  read -p    "AWS Access Key ID : "     AWS_ACCESS_KEY
  read -s -p "AWS Secret Access Key : " AWS_SECRET_KEY
  echo ""
  read -p    "Broker URL (amqps://...) : " BROKER_URL
  read -p    "Bucket name : "              BUCKET_NAME

  # Active KV et stocke les secrets
  vault secrets enable -path=secret kv-v2 2>/dev/null || true

  vault kv put secret/image-api \
    aws_access_key_id="$AWS_ACCESS_KEY" \
    aws_secret_access_key="$AWS_SECRET_KEY" \
    broker_url="$BROKER_URL" \
    bucket_name="$BUCKET_NAME"

  log "Secrets stockés"

  # Politique d'accès
  vault policy write image-api - << 'EOF'
path "secret/data/image-api" {
  capabilities = ["read"]
}
EOF
  log "Politique image-api créée"

  # Auth JWT pour Nomad
  vault auth enable jwt 2>/dev/null || true

  vault write auth/jwt/config \
    jwks_url="http://${LEADER_IP}:4646/.well-known/jwks.json" \
    jwt_supported_algs="RS256,EdDSA"

  vault write auth/jwt/role/nomad-workloads \
    role_type="jwt" \
    bound_audiences="vault.io" \
    user_claim="/nomad_job_id" \
    user_claim_json_pointer=true \
    token_policies="image-api" \
    token_period="30m"

  log "Auth JWT configurée"

  log ""
  log "=== LEADER CONFIGURÉ ==="
  log ""
  log "⚠️  Pour les autres VMs :"
  log "   1. Lance ce serveur HTTP pour partager le CA :"
  log "      cd /opt/vault/tls && python3 -m http.server 9999"
  log "   2. Lance le script sur chaque worker :"
  log "      sudo ./setup.sh worker"
  log "   3. Arrête le serveur HTTP une fois toutes les VMs configurées"

# ============================================================
# ÉTAPE 6 : Join du cluster Vault (worker)
# ============================================================
else
  log "=== Étape 6 : Rejoindre le cluster Vault ==="

  vault operator raft join \
    -leader-ca-cert=@/opt/vault/tls/ca.crt \
    "https://${LEADER_IP}:8200"

  log "Rejoint le cluster ✓"
  log ""
  log "⚠️  Lance maintenant dans un autre terminal :"
  log "   export VAULT_ADDR=https://${VM_IP}:8200"
  log "   export VAULT_CACERT=/opt/vault/tls/ca.crt"
  log "   vault operator unseal  (3 fois avec les clés de vm1)"
  log ""
  read -p "Appuie sur ENTER une fois Vault unsealed..."

  until vault status 2>/dev/null | grep -q "Sealed.*false"; do
    log "Vault encore sealed, attente..."
    sleep 3
  done

  log ""
  log "=== WORKER CONFIGURÉ ==="
  log "Vérifie sur vm1 : vault operator raft list-peers"
fi

log ""
log "=== INSTALLATION TERMINÉE sur $VM_NAME ==="
