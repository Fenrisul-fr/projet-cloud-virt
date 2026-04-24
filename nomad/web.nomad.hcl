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
      provider = "consul"
      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "3s"
      }
      tags = [
	"traefik.enable=true",
	"traefik.http.routers.web.rule=PathPrefix(`/`)",
        "traefik.http.routers.web.priority=1", 
	"traefik.http.services.web.loadbalancer.server.port=3000"]
    }

    task "web" {
      driver = "docker"

      config {
        image = "fenrisul/projet-cloud-pailhe:web"
        ports = ["http"]
        volumes = [
	   "local/config.json:/dist/config.json", #modifie le config.json
	   "local/config.json:/public/config.json"#dans le build de l'image
        ]
      }
      template {
        data = <<EOF
{
  "endpoint": "https://web.pailhe.maurice-cloud.fr/" # pour utiliser l'ip flottante
}
EOF
	destination = "local/config.json"
      }

      resources {
        cpu    = 128
        memory = 256
      }
    }
  }
}
