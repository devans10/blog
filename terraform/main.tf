provider "digitalocean" {
  token = "${var.do_token}"
}

module "kubernetes" {
  source = "./kubernetes"
  cluster_name = "${var.cluster_name}"
}

provider "kubernetes" {
  host = "${module.kubernetes.cluster_endpoint}"

  client_certificate = "${module.kubernetes.client_certificate}"
  client_key = "${module.kubernetes.client_key}"
  cluster_ca_certificate = "${module.kubernetes.cluster_ca_certificate}"
}

module "deployment" {
  source = "./deployment"
  docker_server = "${var.docker_server}"
  docker_username = "${var.docker_username}"
  docker_password = "${var.docker_password}"
  docker_email = "${var.docker_email}"
  image = "${var.image}"
}

module "dns" {
  source = "./dns"
  sitename = "${var.sitename}"
  ipaddress = "${module.deployment.loadbalancer_ip}"
}
