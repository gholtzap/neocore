variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "tenant_id" {
  type = string
}

variable "tenant_name" {
  type = string
}

variable "server_type" {
  type    = string
  default = "cx32"
}

variable "location" {
  type    = string
  default = "nbg1"
}

variable "image" {
  type    = string
  default = "ubuntu-24.04"
}

variable "ssh_key_ids" {
  type    = list(number)
  default = []
}

variable "ghcr_registry" {
  type    = string
  default = "ghcr.io/gholtzap/5g-core"
}

variable "mcc" {
  type    = string
  default = "999"
}

variable "mnc" {
  type    = string
  default = "70"
}
