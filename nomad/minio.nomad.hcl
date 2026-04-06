# ============================================================
# minio.nomad.hcl
# Job Nomad pour MinIO (stockage objet compatible S3)
#
# MinIO expose deux ports :
#   - 9000 : API S3 (utilisée par l'api et le worker)
#   - 9001 : Console web d'administration
# ============================================================

job "minio" {
  datacenters = ["dc1"]
  type        = "service"

  group "minio" {
    count = 1

    # -------------------------------------------------------
    # Contrainte de placement
    # On veut que MinIO tourne toujours sur la MÊME VM pour que
    # son volume persistant soit accessible. Sans ça, Nomad
    # pourrait déplacer MinIO sur une autre VM après un redémarrage
    # et perdre les données.
    #
    # Ici on cible une VM avec le tag "storage" dans ses métadonnées.
    # Ajouter meta { "vm.type" = "storage" } dans le nomad-client.hcl
    # de la VM dédiée au stockage.
    # -------------------------------------------------------
    

    #ce sera pour la persistence plus tard
    #constraint {
    #  attribute = "${meta.vm.type}"
    #  value     = "storage"
    #}

    network {
      port "api" {
        static = 9000
        to     = 9000
      }
      port "console" {
        static = 9001
        to     = 9001
      }
    }

    service {
      name = "minio"
      port = "api"

      check {
        type     = "http"
        path     = "/minio/health/live"
        interval = "10s"
        timeout  = "3s"
      }
    }

    task "minio" {
      driver = "docker"

      config {
        image   = "quay.io/minio/minio"
        ports   = ["api", "console"]
        command = "server"
        args    = ["/data", "--console-address", ":9001"]

        # -------------------------------------------------------
        # Volume persistant
        # Monte le répertoire /opt/minio-data de l'hôte dans
        # le conteneur à /data. Les données survivent aux redémarrages
        # du conteneur.
        #
        # IMPORTANT : Ce dossier doit exister sur la VM hôte :
        #   sudo mkdir -p /opt/minio-data
        #   sudo chown -R nobody:nobody /opt/minio-data
        # -------------------------------------------------------
        volumes = [
          "/opt/minio-data:/data"
        ]
      }

      # -------------------------------------------------------
      # Variables d'environnement
      # En prod, ces valeurs ne doivent PAS être en clair ici.
      # Voir la section "Vault" plus bas dans ce fichier pour
      # la version sécurisée.
      # -------------------------------------------------------
      env {
        MINIO_ROOT_USER     = "minioadmin"       # À remplacer
        MINIO_ROOT_PASSWORD = "minioadmin"    # À remplacer par Vault
      }

      resources {
        cpu    = 512
        memory = 512
      }
    }
  }
}

# ============================================================
# VERSION AVEC VAULT (recommandée en prod)
# Remplacer le bloc env {} ci-dessus par :
#
#   template {
#     data = <<EOF
# {{ with secret "secret/data/minio" }}
# MINIO_ROOT_USER={{ .Data.data.root_user }}
# MINIO_ROOT_PASSWORD={{ .Data.data.root_password }}
# {{ end }}
# EOF
#     destination = "secrets/minio.env"
#     env         = true
#   }
#
# Et stocker les secrets dans Vault :
#   vault kv put secret/minio root_user=... root_password=...
# ============================================================
