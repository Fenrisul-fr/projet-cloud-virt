datacenter = "dc1"
data_dir   = "/opt/nomad/data"

# Active le mode client
client {
  enabled = true

  # Métadonnées de cette VM : permet de cibler des jobs sur
  # des VMs spécifiques via les "constraints" dans les jobs.
 
  #nomad démarre pas sans ça
  options = {
    "fingerprint.denylist" = "env_aws"
  } 

  meta {
    "vm.type" = "standard"
  }
}

# Active le mode server
server {
  enabled          = true
  # Nombre de servers pour élire un leader
  bootstrap_expect = 3
}
# Intégration Consul : même agent local
consul {
  address = "127.0.0.1:8500"
}

vault {
  enabled               = true
  address               = "https://192.168.24.101:8200"  #addr du leader
  ca_file               = "/opt/vault/tls/ca.crt"
  jwt_auth_backend_path = "jwt"
}

# Configuration du driver Docker
# Nomad utilise Docker pour lancer les conteneurs
plugin "docker" {
  config {
    # Autorise les conteneurs à accéder au réseau de l'hôte
    # (nécessaire pour que Consul DNS fonctionne depuis les conteneurs)
    allow_privileged = false

    # Volumes autorisés (je pense pas en avoir besoin puisque j'utilise le bucket S3)
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
