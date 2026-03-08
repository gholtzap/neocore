output "server_id" {
  value = hcloud_server.core.id
}

output "public_ip" {
  value = hcloud_server.core.ipv4_address
}

output "status" {
  value = hcloud_server.core.status
}

output "server_type" {
  value = hcloud_server.core.server_type
}

output "amf_endpoint" {
  value = "${hcloud_server.core.ipv4_address}:38412"
}

output "upf_endpoint" {
  value = "${hcloud_server.core.ipv4_address}:2152"
}

output "web_ui_url" {
  value = "http://${hcloud_server.core.ipv4_address}:3001"
}
