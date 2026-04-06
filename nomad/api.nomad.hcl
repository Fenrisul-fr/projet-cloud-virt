# ============================================================
# api.nomad.hcl
# Job Nomad pour l'API backend ET le worker Celery
#
# Dans le docker-compose, api et worker partagent le même build
# (même Dockerfile, commande différente). On reproduit ça ici :
# deux "groups" dans le même job, qui utilisent la même image.
#
# L'image doit être buildée et pushée sur un registry avant
# de déployer ce job :
#   docker build -t tonusername/image-api:latest ./api
#   docker push tonusername/image-api:latest
# ============================================================

job "image-api" {
  datacenters = ["dc1"]
  type        = "service"

  # -------------------------------------------------------
  # Groupe API
  # Équivalent du service "api" dans docker-compose
  # -------------------------------------------------------
  group "api" {
    count = 1  # Passer à 2+ pour de la haute disponibilité

    network {
      port "http" {
        static = 8080
        to     = 8080
      }
    }

    # -------------------------------------------------------
    # Dépendances via Consul
    # Nomad ne gère pas les "depends_on" comme Docker Compose.
    # À la place, l'application doit elle-même gérer les
    # connexions non disponibles (retry, backoff exponentiel).
    #
    # Cependant, on peut bloquer le démarrage de ce job jusqu'à
    # ce que Redis et MinIO soient healthy dans Consul :
    # -------------------------------------------------------
    service {
      name = "image-api"
      port = "http"

      check {
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "api" {
      driver = "docker"

      config {
        image = "image-api:__IMAGE_TAG__"
          #script bash remplace le tag par le dernier commit de l'image 
        ports = ["http"]
        force_pull = "false"
      }

      # -------------------------------------------------------
      # Variables d'environnement
      # Les adresses Redis et MinIO utilisent Consul DNS :
      #   redis.service.consul  → résolu vers la VM qui fait tourner Redis
      #   minio.service.consul  → résolu vers la VM qui fait tourner MinIO
      #
      # C'est l'équivalent des noms de services dans docker-compose
      # (redis, minio) qui étaient résolus par le DNS Docker interne.
      # -------------------------------------------------------
      env {
        # Celery / Redis
        CELERY_BROKER_URL = "redis://redis.service.consul:6379/0"
        REDIS_URL         = "redis://redis.service.consul:6379/0"

        # MinIO / S3
        S3_ENDPOINT_URL   = "http://minio.service.consul:9000"
        S3_ACCESS_KEY     = "minioadmin"       # À mettre dans Vault en prod
        S3_SECRET_KEY     = "minioadmin123"    # À mettre dans Vault en prod
        S3_BUCKET_NAME    = "images"
      }

      resources {
        cpu    = 256
        memory = 512
      }
    }
  }

  # -------------------------------------------------------
  # Groupe Worker
  # Équivalent du service "worker" dans docker-compose.
  # Même image que l'API, mais commande différente.
  # -------------------------------------------------------
  group "worker" {
    # On peut facilement scaler les workers horizontalement
    # en changeant ce count (ex: count = 3 pour 3 workers en parallèle)
    count = 1

    # Le worker n'expose pas de port réseau (il consomme la file,
    # il ne reçoit pas de connexions entrantes)

    service {
      name = "image-worker"
    }

    task "worker" {
      driver = "docker"

      config {
        image   = "image-api:__IMAGE_TAG__"
        force_pull = "false"
        #comme docker-compose ici
        command = "uv"
        args    = ["run", "--no-dev", "celery", "--app", "image_api.worker.app", "worker"]
      }

      env {
        CELERY_BROKER_URL = "redis://redis.service.consul:6379/0"
        REDIS_URL         = "redis://redis.service.consul:6379/0"
        S3_ENDPOINT_URL   = "http://minio.service.consul:9000"
        S3_ACCESS_KEY     = "minioadmin"
        S3_SECRET_KEY     = "minioadmin123"
        S3_BUCKET_NAME    = "images"
      }

      resources {
        cpu    = 512   
        memory = 1024  
      }
    }
  }
}
