# ============================================================
# redis.nomad.hcl
# Job Nomad pour Redis (remplace le service "redis" du compose)
#
# Redis est un service d'infrastructure (file de messages via
# Celery dans ce projet). On le déploie en "service" Nomad
# avec une seule instance.
# ============================================================

job "redis" {
  # Datacenter cible (doit correspondre à nomad-server.hcl)
  datacenters = ["dc1"]

  # Type "service" = Nomad s'assure que le job tourne en permanence
  # et le redémarre s'il tombe. (Autres types : "batch", "system")
  type = "service"

  group "redis" {
    # Nombre d'instances. 1 suffit pour Redis en dev/staging.
    # Pour de la HA Redis, utiliser Redis Sentinel (hors scope ici).
    count = 1

    # -------------------------------------------------------
    # Réseau
    # Nomad alloue dynamiquement un port sur la VM hôte,
    # puis l'injecte dans le conteneur via une variable d'env.
    # Le label "db" permet de référencer ce port ailleurs dans le job.
    # -------------------------------------------------------
    network {
      port "db" {
        # "static" force le port 6379 sur l'hôte.
        # Sans "static", Nomad choisirait un port aléatoire.
        # Pour Redis, on fixe le port pour que les autres services
        # puissent s'y connecter via Consul DNS.
        static = 6379
        to     = 6379  # Port dans le conteneur
      }
    }

    # -------------------------------------------------------
    # Enregistrement dans Consul
    # Ce bloc dit à Consul : "ce groupe expose un service appelé
    # 'redis', accessible via redis.service.consul:6379"
    # -------------------------------------------------------
    service {
      name = "redis"
      port = "db"

      # Health check : Consul vérifie que Redis répond
      # Si le check échoue, Consul retire ce service de son registre
      # → les autres services ne lui enverront plus de trafic
      check {
        type     = "tcp"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "redis" {
      # Driver Docker : lance un conteneur
      driver = "docker"

      config {
        image = "redis:7.4"
        ports = ["db"]
      }

      # Ressources allouées à ce conteneur sur la VM
      # Nomad refuse de lancer le job si la VM n'a pas ces ressources libres
      resources {
        cpu    = 256  # en MHz
        memory = 256  # en MB
      }
    }
  }
}
