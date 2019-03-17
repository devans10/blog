+++ 
draft = false
date = 2019-03-16T15:43:08-04:00
title = "Kubernetes Nginx Ingress Controller"
description = "Setting up an Nginx Ingress Controller on a Digital Ocean Kubernetes Cluster"
slug = "" 
tags = ["kubernetes", "digitalocean"]
categories = []
externalLink = ""
+++
Now that I have my website setup running on Kubernetes.  I still would like to decrease my costs as much as possible.  The original setup used a Digital Ocean LoadBalancer instance as the Ingress to the Kubernetes Pods.  This works great and is very easy to setup with Terraform.  However, this setup will end up being a bit pricey.  For any additional websites that are setup on this cluster, another LoadBalancer instance will need to be purchased, and the fact that each LoadBalancer instance cost the same as a Droplet on DO, this really won't save me any money.

The solution to this is to use an Nginx Ingress controller that is fronted by a LoadBalancer instance.   

### Setting up the Kubernetes Nginx Ingress Controller

The [Nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/) is maintained by the Kubernetes project.  It is built around the Kubernetes Ingress resource, using a ConfigMap to store the Nginx configuration.

The Nginx Ingress Controller consists of a Pod that runs an Nginx web server and watches the Kubernetes Control Plane for new and updated Ingress Resource objects.

I wanted, and tried, to do all of this via Terraform.  However, there were are some limitations in the Kubernetes terraform provider that prevent all the steps being executed with Terraform.  The Terraform provider does not support setting kubernetes.io/something annotations, as they are normally used by the scheduler.  There is a couple mandatory yaml needed to setup the ingress controller that have these annotaions in them.  Therefore, I was not able to write valid Terraform configurations to replace these.

The first step to setup the Nginx Ingress Controller is to create the mandatory objects

```
$ kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/mandatory.yaml
```

The output from this command shows all the required objects that get created.

```
namespace/ingress-nginx created
configmap/nginx-configuration created
configmap/tcp-services created
configmap/udp-services created
serviceaccount/nginx-ingress-serviceaccount created
clusterrole.rbac.authorization.k8s.io/nginx-ingress-clusterrole created
role.rbac.authorization.k8s.io/nginx-ingress-role created
rolebinding.rbac.authorization.k8s.io/nginx-ingress-role-nisa-binding created
clusterrolebinding.rbac.authorization.k8s.io/nginx-ingress-clusterrole-nisa-binding created
deployment.extensions/nginx-ingress-controller created
```

Next, we deploy the Nginx Ingress

```
$ kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/provider/cloud-generic.yaml
```

This will deploy the nginx-ingress service, which will be a Digital Ocean Loadbalancer instance.

```
$ kubectl get svc --namespace=ingress-nginx
NAME            TYPE           CLUSTER-IP       EXTERNAL-IP       PORT(S)                      AGE
ingress-nginx   LoadBalancer   10.245.222.202   134.209.128.201   80:32725/TCP,443:30659/TCP   122m
```

The external IP should correspond to the IP of the LoadBalancer.

### Install Helm

In addition to changing the ingress type, I also want to add Let's Encrypt certificates to my site.  The only documentation I found on how to do this uses Helm for the installation.  I have not used Helm before, and really know very little about it.  Here are the quick installation steps I used.
 
Install Helm on my local machine

```
$ snap install helm --classic
```

Install tiller into the Kubernetes cluster

```
$ kubectl -n kube-system create serviceaccount tiller
$ kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
$ helm init --service-account tiller
```

### Install Cert-Manager

First, Cert-Managers Custom Resource Definitions must be created in the cluster

```
$ kubectl apply -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.6/deploy/manifests/00-crds.yaml
```

Output:

```
customresourcedefinition.apiextensions.k8s.io/certificates.certmanager.k8s.io created
customresourcedefinition.apiextensions.k8s.io/issuers.certmanager.k8s.io created
customresourcedefinition.apiextensions.k8s.io/clusterissuers.certmanager.k8s.io created
customresourcedefinition.apiextensions.k8s.io/orders.certmanager.k8s.io created
customresourcedefinition.apiextensions.k8s.io/challenges.certmanager.k8s.io created
```

Now we need to add a label to the `kube-system` namespace to enable resource validation using a webhook.

```
$ kubectl label namespace kube-system certmanager.k8s.io/disable-validation="true"
```

And finally, install cert-manager using a helm chart.

```
$ helm install --name cert-manager --namespace kube-system stable/cert-manager
```

Next, we need to create a Let's Encrypt issuer for certificate.

prod_issuer.yaml

```
apiVersion: certmanager.k8s.io/v1alpha1
kind: ClusterIssuer
metadata:
 name: letsencrypt-staging
spec:
 acme:
   # The ACME server URL
   server: https://acme-staging-v02.api.letsencrypt.org/directory
   # Email address used for ACME registration
   email: your_email_address_here
   # Name of a secret used to store the ACME account private key
   privateKeySecretRef:
     name: letsencrypt-staging
   # Enable the HTTP-01 challenge provider
   http01: {}
```

```
$ kubectl create -f prod_issuer.yaml
```

### Create the Ingress

First, I need to change the current service to my blog from a LoadBalancer to a ClusterIP.  I edited the Terraform configuration for that resource

```
resource "kubernetes_service" "blog" {
  metadata {
    name = "blog"
  }
  spec {
    selector {
      app = "${kubernetes_deployment.blog.metadata.0.labels.app}"
    }
    port {
      port = 80
      target_port = 80
    }
  }
}
```

I did run into a problem here. The previous service type was a LoadBalancer, which has a node port, but in the ClusterIP resource, a node port value is not allowed.  So to make this change, I actually destroyed my whole infrastructure and recreated it.
 

Now that we have all the needed parts we can create the Ingress object.

blog_ingress.yaml

```
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: blog-ingress
  annotations:
    kubernetes.io/ingress.class: nginx
    certmanager.k8s.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - www.daveevans.us
    secretName: letsencrypt-prod
  rules:
  - host: www.daveevans.us
    http:
      paths:
      - backend:
          serviceName: blog
          servicePort: 80
```

```
$ kubectl apply -f blog_ingress.yaml
```

Once the certificate is issued, the site is using https, and it automatically redirects port 80 to 443.


