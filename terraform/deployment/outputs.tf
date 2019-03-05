output "loadbalancer_ip" {
  value = "${kubernetes_service.blog.load_balancer_ingress.0.ip}"
}
