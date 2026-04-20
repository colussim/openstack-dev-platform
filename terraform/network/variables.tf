# ─── Auth ─────────────────────────────────────────────────────────────────────

variable "auth_url" {
  description = "URL authentification Keystone"
  default     = "http://192.168.2.14/identity/v3"
}

variable "user_name" {
  default = "admin"
}

variable "password" {
  sensitive   = true
  type      = string
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

# ─── Public Network ────────────────────────────────────────────────────────────

variable "public_network_name" {
  default = "public"
}

variable "public_subnet_name" {
  default = "public-subnet"
}

variable "public_cidr" {
  default = "192.168.0.0/24"
}

variable "public_gateway" {
  default = "192.168.0.254"
}

variable "floating_ip_start" {
  default = "192.168.0.80"
}

variable "floating_ip_end" {
  default = "192.168.0.89"
}

# ─── Private Network ─────────────────────────────────────────────────────────────

variable "private_network_name" {
  default = "private"
}

variable "private_subnet_name" {
  default = "private-subnet"
}

variable "private_cidr" {
  default = "10.11.12.0/24"
}

variable "private_gateway" {
  default = "10.11.12.1"
}

variable "router_name" {
  default = "router1"
}

variable "dns_nameservers" {
  default = ["192.168.0.254", "8.8.8.8"]
}
