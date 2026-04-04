# ============================================================
# web.nomad.hcl
# Job Nomad pour le frontend web
# ============================================================

job "web" {
  datacenters = ["dc1"]
  type        = "service"

  group "web" {
    count = 1

    network {
      port "http" {
        static = 3000
        to     = 3000
      }
    }

    service {
      name = "web"
      port = "http"

      check {
        type     = "http"
        path     = "/health/live"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "web" {
      driver = "docker"

      config {
        image = "tonusername/image-web:latest"
        ports = ["http"]
      }

      # Le frontend doit savoir où appeler l'API.
      # En prod, on passerait plutôt par un reverse proxy (Traefik,
      # Nginx) devant l'API, mais pour simplifier :
      env {
        # URL publique de l'API (à adapter selon ton setup réseau)
        API_URL = "http://image-api.service.consul:8080"
      }

      resources {
        cpu    = 128
        memory = 256
      }
    }
  }
}
