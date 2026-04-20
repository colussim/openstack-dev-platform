terraform {
  required_version = ">= 1.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.0"
    }
  }
}

provider "openstack" {
  auth_url    = var.auth_url
  user_name   = var.user_name
  password    = var.password
  tenant_name = var.tenant_name
  domain_name = var.domain_name
  region      = var.region

  endpoint_type = "public"
  endpoint_overrides = {
    network  = "http://192.168.2.14/networking/v2.0/"
    compute  = "http://192.168.2.14/compute/v2.1/"
    identity = "http://192.168.2.14/identity/v3/"
    image    = "http://192.168.2.14/image/v2/"
    volume   = "http://192.168.2.14/volume/v3/"
  }
}
