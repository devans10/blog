#locals {
#  dockercfg = {
#    "${var.docker_server}" = {
#      email    = var.docker_email
#      username = var.docker_username
#      password = var.docker_password
#    }
#  }
#}
resource "kubernetes_secret" "regsecret" {
  metadata {
    name = "regsecret"
  }

  data = {
    ".dockerconfigjson" = "${file("~/.docker/config.json")}"
  }

  type = "kubernetes.io/dockerconfigjson"
}

resource "kubernetes_deployment" "blog" {
  metadata {
    name = "blog"
    labels = {
      app = "blog"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "blog"
      }
    }

    template {
      metadata {
        labels = {
          app = "blog"
        }
      }

      spec {
        container {
           name = "blog"
           image = var.image
           image_pull_policy = "Always"
           port {
             container_port = "80"
           }
         }
         image_pull_secrets {
           name = kubernetes_secret.regsecret.metadata.0.name
         }
       }
     }
   }
}


resource "kubernetes_service" "blog" {
  metadata {
    name = "blog"
  }
  spec {
    selector = {
      app = kubernetes_deployment.blog.metadata.0.labels.app
    }
    port {
      port = 80
      target_port = 80
    }
  }
}


