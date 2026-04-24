ui            = true
disable_mlock = true

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vm1"  # vm2, vm3 selon la VM
}

api_addr     = "https://192.168.24.101:8200"  # IP de la VM
cluster_addr = "https://192.168.24.101:8201"  # IP de la VM

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_cert_file      = "/opt/vault/tls/tls.crt"
  tls_key_file       = "/opt/vault/tls/tls.key"
  tls_client_ca_file = "/opt/vault/tls/ca.crt"
}


