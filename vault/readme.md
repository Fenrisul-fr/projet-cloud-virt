

# ATTENTION
# Avec le vault actif, si une vm tombe ou est reboot il faut relancer vault et unseal à nouveau
# pour qu'elle puisse recevoir les tokens et donc executer les jobs nomads 




# installer vault sur toutes les vm
sudo apt install vault

#copier la config vault.hcl sur toutes les vm dans /etc/vault.d/vault.hcl

# sur une vm (la 1 ou leader)
vault operator init 

--> stocker les credentials (unseal et token login)


# 1. Génère le CA
openssl genrsa -out /opt/vault/tls/ca.key 4096
openssl req -x509 -new -nodes \
  -key /opt/vault/tls/ca.key \
  -days 3650 \
  -out /opt/vault/tls/ca.crt \
  -subj "/CN=vault-ca"

génère ca.key et ca.crt sur vm1
il faut les copier sur les autres vm dans le dossier /opt/vault/tls
puis

# sur vm1,vm2 et vm3 générer le CA signé
openssl genrsa -out /opt/vault/tls/tls.key 4096
openssl req -new \
  -key /opt/vault/tls/tls.key \
  -out /tmp/vmX.csr \
  -subj "/CN=vault-vmX"
openssl x509 -req -in /tmp/vmX.csr \
  -CA /opt/vault/tls/ca.crt \
  -CAkey /opt/vault/tls/ca.key \
  -CAcreateserial \
  -out /opt/vault/tls/tls.crt \
  -days 365 \
  -extfile <(echo "subjectAltName=IP:192.168.24.10X,IP:127.0.0.1")


sudo chown vault:vault /opt/vault/tls/tls.key /opt/vault/tls/tls.crt
sudo systemctl restart vault


#!!! changer les ip et les noms des vm !!!


# pour débug 
    openssl x509 -in /opt/vault/tls/tls.crt -noout -text | grep -A3 "Subject Alternative\|Subject:"

#doit apparaitre l'adresse ip de la vm et son CN

    openssl verify -CAfile /opt/vault/tls/ca.crt /opt/vault/tls/tls.crt
#affiche ok si le tls est bien signé par le CA (si on a bien le bon ca de la vm1 sur les autres vm)



# Sur vm1 — unseal le leader
export VAULT_ADDR="https://192.168.24.101:8200"
export VAULT_CACERT="/opt/vault/tls/ca.crt"
vault operator unseal  # clé 1 voir le fichier secrets identifiants vm1 
vault operator unseal  # clé 2
vault operator unseal  # clé 3


# Sur vm2 et vm3 — rejoindre puis unseal
export VAULT_ADDR="https://192.168.24.10X:8200"
export VAULT_CACERT="/opt/vault/tls/ca.crt"
vault operator raft join -leader-ca-cert=@/opt/vault/tls/ca.crt https://192.168.24.101:8200
vault operator unseal  # clé 1
vault operator unseal  # clé 2
vault operator unseal  # clé 3




# stocker les secrets dans vault

vault secrets enable -path=secret kv-v2
#ouvre dossier secret dans lequel on va stocker les mdp

vault kv put secret/image-api \
  aws_access_key_id="ACCESS_KEY" \
  aws_secret_access_key="SECRET_KEY" \
  broker_url="amqps://user:pass@rabbitmq.maurice-cloud.fr:5671/pailhe" \
  bucket_name="cloud-virt-mai-pailhe-images"


vault policy write image-api - <<EOF
path "secret/data/image-api" {
  capabilities = ["read"]
}
EOF

vault auth enable jwt

vault write auth/jwt/config \
  jwks_url="http://192.168.24.101:4646/.well-known/jwks.json" \  #addr de mon leader
  jwt_supported_algs="RS256,EdDSA" 


vault write auth/jwt/role/image-api-role \
  role_type="jwt" \
  bound_audiences="vault.io" \
  user_claim="/nomad_job_id" \
  user_claim_json_pointer=true \
  token_policies="image-api" \
  token_period="30m"

# ajout dans les configs nomad.hcl 
vault {
  enabled   = true
  address   = "https://192.168.24.101:8200"
  ca_file   = "/opt/vault/tls/ca.crt"
  jwt_auth_backend_path = "jwt" 
}


# dans les jobs nomad
au niveau des groups (api/worker/web)
  identity {
    name = "vault_default"
    aud  = ["vault.io"]
    ttl  = "1h"
  }
  vault {
    policies = ["image-api"] (ou "web)
    role = "image-api-role"
  }