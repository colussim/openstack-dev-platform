# ─── Auth ─────────────────────────────────────────────────────────────────────

variable "auth_url" {
  default = "http://192.168.2.14/identity/v3"
}

variable "user_name" {
  default = "admin"
}

variable "password" {
 type      = string
  sensitive = true
}

variable "tenant_name" {
  default = "admin"
}

variable "domain_name" {
  default = "Default"
}

variable "region" {
  default = "RegionOne"
}

# ─── Network references ───────────────────────────────────────────────────────

variable "public_network_name" {
  default = "public"
}

variable "private_network_name" {
  default = "private"
}

variable "private_subnet_name" {
  default = "private-subnet"
}

# ─── Instance ─────────────────────────────────────────────────────────────────

variable "instance_name" {
  default = "web-test"
}

variable "image_name" {
  default = "centos-9-stream-arm64"
}

variable "flavor_name" {
  default = "m1.small"
}

variable "public_key_path" {
  default = "~/.ssh/id_ed25519_openstack.pub"
}

variable "public_key_name" {
  default = "openstack"
}

variable "instance_password" {
  sensitive = true
  type      = string
}
