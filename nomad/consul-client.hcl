# ============================================================
# consul-client.hcl
# Configuration du client Consul
#
# Un agent Consul "client" tourne sur chaque VM qui fait tourner
# des jobs Nomad. Son rôle :
#   - Enregistrer les services qui tournent sur cette VM
#   - Répondre aux requêtes DNS locales (ex: redis.service.consul)
#   - Relayer les health checks vers les servers Consul
#
# Les jobs Nomad communiquent avec Consul via cet agent local
# (127.0.0.1:8500), pas directement avec les servers.
# ============================================================

node_name = "nomad-client-1"  # Changer par VM : nomad-client-2, etc.
data_dir  = "/opt/consul/data"

# Ce nœud est un client (pas un server)
server = false

bind_addr  = "0.0.0.0"
client_addr = "0.0.0.0"

# Même clé de chiffrement que les servers
encrypt = "REMPLACER_PAR_consul_keygen"

# Adresses des servers Consul pour rejoindre le cluster
retry_join = [
  "10.0.1.1",
  "10.0.1.2",
  "10.0.1.3",
]

# ---------------------------------------------------------------
# Configuration DNS
# L'agent Consul répond aux requêtes DNS sur le port 8600.
# Pour que les conteneurs puissent résoudre "redis.service.consul",
# il faut configurer le système pour rediriger les requêtes .consul
# vers Consul.
#
# Avec systemd-resolved (Ubuntu/Debian moderne) :
#   /etc/systemd/resolved.conf.d/consul.conf :
#     [Resolve]
#     DNS=127.0.0.1:8600
#     Domains=~consul
# ---------------------------------------------------------------

ports {
  dns = 8600  # Port DNS de Consul
}

log_level = "INFO"
log_file  = "/var/log/consul/consul.log"
