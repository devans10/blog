provider "kubernetes" {}
provider "digitalocean" {
  token = "${var.do_token}"
}

module "kubernetes" {
  source = "./kubernetes"
  docker_server = "${var.docker_server}"
  docker_username = "${var.docker_username}"
  docker_password = "${var.docker_password}"
  docker_email = "${var.docker_email}"
}

module "dns" {
  source = "./dns"
  sitename = "${var.sitename}"
  ipaddress = "${module.kubernetes.loadbalancer_ip}"
}
