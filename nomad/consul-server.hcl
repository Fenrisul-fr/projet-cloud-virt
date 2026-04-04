# ============================================================
# consul-server.hcl
# Configuration du serveur Consul
#
# Consul a deux rôles distincts :
#   - "server" : cerveau du cluster, stocke l'état, élit un leader
#   - "client" : tourne sur chaque VM Nomad, relaie vers les servers
#
# En prod minimale : 3 servers Consul (tolérance à 1 panne)
# ============================================================

# Nom unique de ce nœud dans le cluster
node_name = "consul-server-1"

# Dossier où Consul stocke son état persistant (membres, services...)
data_dir = "/opt/consul/data"

# Ce nœud est un server (pas un simple client)
server = true

# Nombre de servers nécessaires pour élire un leader.
# Doit être identique sur tous les servers du cluster.
# Règle : (nombre de servers / 2) + 1
# Avec 3 servers → bootstrap_expect = 3
bootstrap_expect = 3

# Interface réseau sur laquelle Consul écoute.
# "0.0.0.0" = toutes les interfaces (OK pour un réseau privé fermé)
# En prod réelle, remplacer par l'IP privée de la VM : "10.0.1.x"
bind_addr = "0.0.0.0"

# Active l'interface HTTP de Consul (API + UI)
# Écoute sur toutes les interfaces, port 8500
client_addr = "0.0.0.0"

# Active l'interface web de Consul (consul.mondomaine.com:8500/ui)
ui_config {
  enabled = true
}

# Chiffrement des communications entre membres du cluster.
# Générer avec : consul keygen
# Tous les membres du cluster doivent avoir la même clé.
encrypt = "REMPLACER_PAR_consul_keygen"

# Liste des adresses IP des autres servers Consul pour former le cluster.
# Consul va contacter ces adresses au démarrage pour rejoindre le cluster.
retry_join = [
  "10.0.1.1",  # IP privée du server Consul 1
  "10.0.1.2",  # IP privée du server Consul 2
  "10.0.1.3",  # IP privée du server Consul 3
]

# Configuration des logs
log_level = "INFO"
log_file  = "/var/log/consul/consul.log"

# Active les checks de performance (optionnel mais utile)
performance {
  raft_multiplier = 1
}
