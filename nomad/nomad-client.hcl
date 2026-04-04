# ============================================================
# nomad-client.hcl
# Configuration du client Nomad (exécute les jobs)
#
# Tourne sur chaque VM qui va faire tourner des conteneurs.
# Peut tourner sur la même VM qu'un server Nomad (petit cluster)
# ou sur des VMs dédiées (grand cluster).
# ============================================================

datacenter = "dc1"
data_dir   = "/opt/nomad/data"

# Active le mode client
client {
  enabled = true

  # Métadonnées de cette VM : permet de cibler des jobs sur
  # des VMs spécifiques via les "constraints" dans les jobs.
  # Exemple : forcer minio sur une VM avec un grand disque.
  meta {
    "vm.type" = "standard"
  }
}

# Intégration Consul : même agent local
consul {
  address = "127.0.0.1:8500"
}

# Configuration du driver Docker
# Nomad utilise Docker pour lancer les conteneurs
plugin "docker" {
  config {
    # Autorise les conteneurs à accéder au réseau de l'hôte
    # (nécessaire pour que Consul DNS fonctionne depuis les conteneurs)
    allow_privileged = false

    # Volumes autorisés (pour minio_data)
    volumes {
      enabled = true
    }
  }
}

advertise {
  http = "{{ GetPrivateIP }}"
}

log_level = "INFO"
log_file  = "/var/log/nomad/nomad.log"
