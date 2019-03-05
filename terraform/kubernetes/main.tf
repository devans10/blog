data "digitalocean_kubernetes_cluster" "production" {
  name = "${var.cluster_name}"
}
