job "traefik" {
  datacenters = ["dc1"]
  type	      = "system" #sur chaque vm pour avoir le reverse proxy quelle que soit l'ip flottante

  group "traefik" {
    network {
      port "http" {
        static = 8080
      }
    }

    task "traefik" {
      driver = "docker"

      config {
	image = "traefik:v3.0"
	network_mode = "host"
	args = [
	"--providers.consulcatalog=true",
	"--providers.consulcatalog.endpoint.address=127.0.0.1:8500",
	"--entrypoints.web.address=:8081", #reverse proxy sur 8081
	"--api.dashboard=true",
	"--api.insecure=true",
	"--entryPoints.traefik.address=:8082", #dashboard 
	"--log.level=DEBUG"
        ]
     }
     resources {
        cpu    = 200
        memory = 128
      }
    }
  }
}
