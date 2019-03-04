+++ 
draft = false
date = 2019-03-03T21:58:41-05:00
title = "Deploying My Blog on Kubernetes"
description = "How and why I moved my blog site to Kubernetes"
slug = "" 
tags = ["kubernetes", "terraform"]
categories = []
externalLink = ""
+++
So its been quite awhile since I posted anything. That is because I have been very busy with some personal projects and doing a lot of studying of some new technologies.  

As you can see I have completely redone my site.  The previous site was running on the Ghost platform, which was spun up using a one-click deployment from [DigitalOcean.](https://www.digitalocean.com)  Ghost was a good platform. I liked doing the posts in markdown, and it was easy to use.  However, like a lot of the blogging and content managment platforms it requires a database on the backend.  This made it necessary to have a beefier DigitalOcean droplet than I wanted to maintain, for a site that isn't getting all that much traffic.  In addition, I have been working on a couple projects that I want to run individual project sites for, and it didn't make sense for me to spin up different droplets for those, when they could easily fit on resources I'm already paying for.

#### Enter Hugo
I decided to move my entire site over to [Hugo](https://gohugo.io), a very fast, static site generator written in Go.  It was very easy to move everything in Ghost over to Hugo since the posts in both are done in markdown.  The only thing that was a bit of a pain was manually entering the post metadata, but, all in all, it wasn't that bad.  If you are interested in Hugo, the instuctions for getting started are [here](https://gohugo.io/getting-started/quick-start/).  

The other benefit of moving the site to this new framework is it makes it much easier to store the source code for my site in [Github](https://github.com).  Which will also give me the opportunity to do some automated deployments of my site in the future.

#### Docker
I now have a statically generated site, with the source code in Github. This makes it very easy to run the site within a Docker container.

In the Dockerfile, we first create a container and install the Hugo extended version from source and pygments, which is required for the source code blocks.  Then, hugo is run on the site to generate the static files.  Next, a new container is built from the nginx alpine image, the static files generated in the first stage are then copied to the new container.

Once the container is built, I push it up to my private docker hub registry.

```docker
FROM ubuntu:latest as STAGEONE

# install hugo
ENV HUGO_VERSION=0.54.0
ADD https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz /tmp/
RUN tar -xf /tmp/hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz -C /usr/local/bin/

RUN apt-get update
RUN apt-get install -y python3-pygments

# build site
COPY src /source
RUN hugo --source=/source/ --destination=/public/

FROM nginx:stable-alpine
COPY --from=STAGEONE /public/ /usr/share/nginx/html/
EXPOSE 80
```


#### Kubernetes
If I'm going to run the site in a Docker container, why not run it on Kubernetes.  Digital Ocean recently released limited availability of managed Kubernetes clusters.  Spinning up a new cluster took about 5 minutes, and was much cheaper than running the managed services from AWS.  They only charge for the droplets, block storage, and load balancers. There is no additional charge for the cluster itself.

So, I know that a lot of people are thinking that it is complete overkill to run a small website on Kubernetes.  You are completely right. This is way overboard.  However, I have been studying and working with Kubernetes a lot recently, and I want to learn as much as I can.  This is just the next stage in my education.  I need to run something in "Production", so I can learn to more about it and find out its shortcomings and advantages.

#### Deployment with Terraform
Now that I have my cluster up and running, deploying the site should be a snap. However, since I'm using this as a major learning exercise, I'm also going to use another technology I have been working with lately... Terraform.

_Note: As I'm writing this, I just realized I should have created the entire Kubernetes cluster on DigitalOcean using Terraform.  I guess I just found my next task_

For the deployment I created two modules, dns and kubernetes.  The `main.tf` of the kubernetes module, creates a namespace, a docker registry secret, a deployment, and a service. It then outputs the IP address of the service, which is used in the dns module.

```terraform
locals {
  dockercfg = {
    "${var.docker_server}" = {
      email    = "${var.docker_email}"
      username = "${var.docker_username}"
      password = "${var.docker_password}"
    }
  }
}

resource "kubernetes_namespace" "blog" {
  metadata {
    name = "blog"
  }
}

resource "kubernetes_secret" "regsecret" {
  metadata {
    name = "regsecret"
    namespace = "${kubernetes_namespace.blog.metadata.0.name}"
  }

  data {
    ".dockercfg" = "${ jsonencode(local.dockercfg) }"
  }

  type = "kubernetes.io/dockercfg"
}

resource "kubernetes_deployment" "blog" {
  metadata {
    name = "blog"
    namespace = "${kubernetes_namespace.blog.metadata.0.name}"
    labels {
      app = "blog"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels {
        app = "blog"
      }
    }

    template {
      metadata {
        labels {
          app = "blog"
        }
      }

      spec {
        container {
           name = "blog"
           image = "${var.image}"
           image_pull_policy = "Always"
           port {
             container_port = "80"
           }
         }
         image_pull_secrets {
           name = "${kubernetes_secret.regsecret.metadata.0.name}"
         }
       }
     }
   }
}

resource "kubernetes_service" "blog" {
  metadata {
    name = "blog"
    namespace = "${kubernetes_namespace.blog.metadata.0.name}"
  }
  spec {
    selector {
      app = "${kubernetes_deployment.blog.metadata.0.labels.app}"
    }
    session_affinity = "ClientIP"
    port {
      port = 80
      target_port = 80
    }

    type = "LoadBalancer"
  }
}
```

The dns module creates the A record for the web site in the Digital Ocean domain DNS zone, and outputs the fqdn of the record created.

```terraform
resource "digitalocean_record" "sitename" {
  domain = "daveevans.us"
  type = "A"
  name = "${var.sitename}"
  value = "${var.ipaddress}"
}
```

I call both both modules from the `main.tf` at the root.

```terraform
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
```


Now I have my new blog website, build with Hugo, running on Kubernetes, deployed with Terraform.  It was a fun weekend.
