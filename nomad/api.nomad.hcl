# ============================================================
# api.nomad.hcl
# Job Nomad pour l'API backend ET le worker Celery
# L'image doit être buildée et pushée sur un registry avant
# de déployer ce job 
# ============================================================

job "image-api" {
  datacenters = ["dc1"]
  type        = "service"

  # -------------------------------------------------------
  # Groupe API
  # -------------------------------------------------------
  group "api" {
    count = 2  # Passer à 2+ pour de la haute disponibilité

    network {
      port "http" {
        to     = 8080
      }
    }
    service {
      name = "image-api"
      port = "http"
      provider = "consul"
      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "3s"
      }
      tags = [
	"traefik.enable=true",
	"traefik.http.routers.api.rule=PathPrefix(`/image`)", #nom du bucket
	"traefik.http.routers.api.priority=10" #parsed avant "/" pour le web basique
	]
    }

    task "api" {
      driver = "docker"
      identity {
	name     = "vault_default"
	aud      = ["vault.io"]
        ttl      = "1h"
      }
      vault {
	 policies = ["image-api"]
	 role     = "image-api-role"
      }
      
      config {
        image = "fenrisul/projet-cloud-pailhe:latest"
        ports = ["http"]
      }
   
      template {
    data = <<EOF
{{ with secret "secret/data/image-api" }}
AWS_ACCESS_KEY_ID={{ .Data.data.aws_access_key_id }}
AWS_SECRET_ACCESS_KEY={{ .Data.data.aws_secret_access_key }}
CELERY_BROKER_URL={{ .Data.data.broker_url }}
S3_BUCKET_NAME={{ .Data.data.bucket_name }}
{{ end }}
EOF
    destination = "secrets/env"
    env         = true
  }

      resources {
        cpu    = 256
        memory = 512
      }
    }
  }

  # -------------------------------------------------------
  # Groupe Worker
  # Même image que l'API, mais commande différente.
  # -------------------------------------------------------
  group "worker" {

    count = 3

    service {
      name = "image-worker"
    }

    task "worker" {
      driver = "docker"

      config {
        image = "fenrisul/projet-cloud-pailhe:latest"
        #comme docker-compose ici
        command = "uv"
        args    = ["run", "--no-dev", "celery", "--app", "image_api.worker.app", "worker"]
      }
      identity {
        name     = "vault_default"
        aud      = ["vault.io"]
        ttl      = "1h"
      }
      vault {
	 policies = ["image-api"]
         role     = "image-api-role"
      }

      template {
    data = <<EOF
{{ with secret "secret/data/image-api" }}
AWS_ACCESS_KEY_ID={{ .Data.data.aws_access_key_id }}
AWS_SECRET_ACCESS_KEY={{ .Data.data.aws_secret_access_key }}
CELERY_BROKER_URL={{ .Data.data.broker_url }}
S3_BUCKET_NAME={{ .Data.data.bucket_name }}
{{ end }}
EOF
    destination = "secrets/env"
    env         = true
  }

      resources {
        cpu    = 512   
        memory = 1024  
      }
    }
  }
}
