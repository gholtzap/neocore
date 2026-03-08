terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_firewall" "core" {
  name = "5g-core-${var.tenant_id}"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "38412"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "38412"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "2152"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "3001"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_server" "core" {
  name        = "5g-core-${var.tenant_id}"
  server_type = var.server_type
  image       = var.image
  location    = var.location
  ssh_keys    = var.ssh_key_ids

  firewall_ids = [hcloud_firewall.core.id]

  labels = {
    tenant_id   = var.tenant_id
    tenant_name = var.tenant_name
    service     = "5g-core"
  }

  user_data = templatefile("${path.module}/cloud-init.yaml.tpl", {
    tenant_id     = var.tenant_id
    ghcr_registry = var.ghcr_registry
    mcc           = var.mcc
    mnc           = var.mnc
  })
}
