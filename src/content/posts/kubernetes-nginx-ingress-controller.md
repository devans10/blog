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
In my previous [post](/posts/deploying-my-blog-on-kubernetes/), I deployed my website on a Kubernetes cluster running on DigitalOcean.  However, I still would like to decrease my costs as much as possible.  The original setup used a Digital Ocean LoadBalancer instance as the Ingress to the Kubernetes Pods.  This works great and is very easy to setup with Terraform.  However, there are a couple downsides to this setup. At this time, the Kubernetes ingress objects cannot take advantage of Let's Encrypt integration with the DigitalOcean LoadBalancer instances, and the solution will end up being a bit pricey.  For any additional websites that are setup on this cluster, another LoadBalancer instance will need to be purchased, and the fact that each LoadBalancer instance cost the same as a Droplet on DO, this really won't save me any money.

The solution to this is to use an Nginx Ingress controller that is fronted by a LoadBalancer instance.  This will provide the reliability of using a LoadBalancer instance, but give the flexiblity of running an Nginx reverse proxy instance that can route traffic by Virtual Host name.

### Setting up the Kubernetes Nginx Ingress Controller

The [Nginx Ingress Controller](https://kubernetes.github.io/ingress-nginx/) is maintained by the Kubernetes project.  It is built around the Kubernetes Ingress resource, using a ConfigMap to store the Nginx configuration.

The Nginx Ingress Controller consists of a Pod that runs an Nginx web server and watches the Kubernetes Control Plane for new and updated Ingress Resource objects.

I wanted (and tried) to do all of this via Terraform.  However, there were are some limitations in the Kubernetes terraform provider that prevent all the steps being executed with Terraform.  The Terraform provider does not support setting kubernetes.io/* annotations, as they are normally used by the scheduler.  There are a couple of mandatory yaml files the need to be applied to setup the ingress controller that have these annotaions in them.  Therefore, I was not able to write valid Terraform configurations to replace these.

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

It is possible to integrate [Let's Encrypt](https://letsencrypt.org/) certificates with the Nginx Ingress controller, but the only documentation I found on how to do this uses Helm for the installation.  I have not used Helm before, and really know very little about it. Here are the quick installation steps I used.
 
##### Install Helm on my local machine.  
There are normal instructions [here](https://helm.sh/docs/using_helm/).  I found it easiest to use the snap.  I prefer snaps for installations like this.  If I don't know much about a peice of software, a snap makes it easy to remove cleanly from my system.

```
$ snap install helm --classic
```

##### Install tiller into the Kubernetes cluster
Tiller is the peice of Helm that does work within the kubernetes cluster.  The below commands create a service account for tiller in the cluster and assign it the `cluster-admin` role.  It then uses `helm` to initialize the installation.

```
$ kubectl -n kube-system create serviceaccount tiller
$ kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
$ helm init --service-account tiller
```

### Install Cert-Manager

`cert-manager` is a service that runs inside the cluster and manages tls certificates for services within the cluster.  There are 3 parts of this service.
+ A cert-manager service that validates certs and renews them when necessary
+ A clusterIssuer service that defines the Certificate Authority to use
+ A certificate resource which defines the cerificates needed for a service.


First, Cert-Manager's Custom Resource Definitions must be created in the cluster

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

Now, we need to add a label to the `kube-system` namespace to enable resource validation using a webhook.

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
 name: letsencrypt-prod
spec:
 acme:
   # The ACME server URL
   server: https://acme-staging-v02.api.letsencrypt.org/directory
   # Email address used for ACME registration
   email: your_email_address_here
   # Name of a secret used to store the ACME account private key
   privateKeySecretRef:
     name: letsencrypt-prod
   # Enable the HTTP-01 challenge provider
   http01: {}
```

```
$ kubectl create -f prod_issuer.yaml
```

*Note: This is an example of the short comings of the Kubernetes Terraform provider.  This is a custom resource created within the cluster.  So obviously there is not a Terraform resource available to set configure it.  On the plus side, this is more of a cluster level function, just like the Nginx Ingress Controller.  So I can configure these for the cluster, then still use Terraform to deploy the applications in the cluster.  However, this feels less like Infrastructure as Code, and more like application deployment.*

### Create the Ingress

First, I need to change the current service to my website from a `LoadBalancer` to a `ClusterIP`.  I edited the Terraform configuration for that resource

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

I did run into a problem here. The previous service type was a LoadBalancer, which has a node port parameter defined, but in the ClusterIP resource, a node port value is not allowed.  Which casued an error when executing `terraform apply`.  So to make this change, I actually destroyed my whole infrastructure and recreated it. Which is a huge benefit of terraform.


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
You can track the issuing of the certificate using

```
$ kubectl describe certificate letsencrypt-prod
```

The Events section will show the events below once the certificate is issued.

```
Events:
  Type    Reason         Age   From          Message
  ----    ------         ----  ----          -------
  Normal  Generated      82s   cert-manager  Generated new private key
  Normal  OrderCreated   82s   cert-manager  Created Order resource "letsencrypt-prod-5342523546254"
  Normal  OrderComplete  37s   cert-manager  Order "letsencrypt-prod-5342523546254" completed successfully
  Normal  CertIssued     37s   cert-manager  Certificate issued successfully
```

If everything works properly the site is now using https, and it automatically redirects port 80 to 443.

One other note, I did notice with the out-of-the box deployment of the Nginx Ingress controller, it has `replicas` set to 1, which causes the DigitalOcean Loadbalancer instance to have one side down.  I increased this to 2, to get a Pod on both nodes of my cluster and cleared the Loadbalancer alert.



