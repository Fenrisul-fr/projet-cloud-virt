# ============================================================
# nomad-server.hcl
# Configuration du server Nomad
#
# Nomad aussi a deux rôles :
#   - "server" : reçoit les jobs, décide où les placer, gère l'état
#   - "client" : exécute les tâches sur la VM
#
# En prod minimale : 3 servers Nomad
# Les servers Nomad peuvent tourner sur les mêmes VMs que les
# servers Consul, ou sur des VMs dédiées.
# ============================================================

# Nom de ce datacenter (doit être identique sur tout le cluster)
datacenter = "dc1"

# Dossier de données persistantes
data_dir = "/opt/nomad/data"

# Active le mode server
server {
  enabled          = true
  # Nombre de servers pour élire un leader (même logique que Consul)
  bootstrap_expect = 1 #pour l'isntant j'en ai qu'un
}

# Intégration avec Consul :
# Nomad utilise Consul pour deux choses :
#   1. Découverte des autres nodes Nomad (auto-join)
#   2. Enregistrement des services des jobs dans Consul
consul {
  address = "127.0.0.1:8500"  # Agent Consul local
}

# Adresse d'écoute pour les communications inter-servers Nomad
# et pour l'API (port 4646)
advertise {
  http = "{{ GetPrivateIP }}"  # Détecte automatiquement l'IP privée
  rpc  = "{{ GetPrivateIP }}"
  serf = "{{ GetPrivateIP }}"
}

log_level = "INFO"
log_file  = "/var/log/nomad/nomad.log"
