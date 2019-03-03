+++
draft = false
date = "2018-10-27T02:00:00Z"
title = "Kubernetes on Raspberry Pi, The Hard Way - Part 2"
description = "Certificate creation for Raspberry Pi Kubernetes cluster."
slug = ""
tags = ["kubernetes", "raspberry pi"]
categories = []
externalLink = ""
+++

[Kubernetes on Raspberry Pi, The Hard Way - Part 1](/posts/kubernetes-on-raspberry-pi-the-hard-way-part-1/)

Now the fun begins...

After the setup of the raspberry pi servers in part 1, I have the hostnames and IPs in the table below.  We now have to create a CA and certificates for all the different pieces of the cluster.  Then create kubeconfigs for the different components to use to connect to the cluster, and distribute everything out to the nodes.  This seems like a *really* long post, but you will see that its a lot of rinse and repeat commands.  All the commands below are run on my local machice.

| Hostname                      | Public IP   | Private IP |
|-------------------------------|-------------|------------|
| k8s-master-1.k8s.daveevans.us |192.168.1.20 | 10.0.0.10  |
| k8s-master-2.k8s.daveevans.us |192.168.1.21 | 10.0.0.11  |
| k8s-master-3.k8s.daveevans.us |192.168.1.22 | 10.0.0.12  |
| k8s-node-1.k8s.daveevans.us   |192.168.1.23 | 10.0.0.13  |
| k8s-node-2.k8s.daveevans.us   |192.168.1.24 | 10.0.0.14  |
| k8s-node-3.k8s.daveevans.us   |192.168.1.25 | 10.0.0.15  |
| kubernetes.k8s.daveevans.us   |192.168.1.26 | 10.0.0.16  |


### Setup our local machine
First, we need to install cfssl which will be used to create all the certificates that we will create.

```sh
$ wget -q --show-progress --https-only --timestamping \
  https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 \
  https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
$ chmod +x cfssl_linux-amd64 cfssljson_linux-amd64
$ sudo mv cfssl_linux-amd64 /usr/local/bin/cfssl
$ sudo mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
$ cfssl version
```

Next, we have to install kubectl that we will use to remotely connect to the cluster later, but in this post we will use it to create the kubeconfigs for the cluster components.

```sh
$ wget https://storage.googleapis.com/kubernetes-release/release/v1.12.0/bin/linux/amd64/kubectl
$ chmod +x kubectl
$ sudo mv kubectl /usr/local/bin/
$ kubectl version --client
```

### Creating the CA and cluster certificates.
Create the CA using the command set below.  You will see a pattern to all these commands.  The first part(s) creates a JSON file that are then fed into the cfssl command to generate the certificates.  I also suggest running these in a seperate directory as it creates a bunch of files.  I created ~/k8s-pi and `cd` into it

```sh
$ {

cat > ca-config.json << EOF
{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}
EOF

cat > ca-csr.json << EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Pittsburgh",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "Pennsylvania"
    }
  ]
}
EOF

cfssl gencert -initca ca-csr.json | cfssljson -bare ca

}
```

Create Admin certificates which will be used to connect remotely to the cluster.

```sh
{

cat > admin-csr.json << EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Pittsburgh",
      "O": "system:masters",
      "OU": "Kubernetes The Hard Way",
      "ST": "Pennsylvania"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  admin-csr.json | cfssljson -bare admin

}
```

Create API Server Certs.  Below we first set a `CERT_HOSTNAME` environment variable that lists all the IPs and hostnames that could be used to connect to the API servers.

```sh
$ CERT_HOSTNAME=10.32.0.1,10.0.0.10,k8s-master-1.k8s.daveevans.us,10.0.0.11,k8s-master-2.k8s.daveevans.us,10.0.0.12,k8s-master-3.k8s.daveevans.us,127.0.0.1,localhost,kubernetes.default


$ {

cat > kubernetes-csr.json << EOF
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Pittsburgh",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Pennsylvania"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${CERT_HOSTNAME} \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes

}
```

Create Controller Certs

```sh
$ {

cat > kube-controller-manager-csr.json << EOF
{
  "CN": "system:kube-controller-manager",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Pittsburgh",
      "O": "system:kube-controller-manager",
      "OU": "Kubernetes The Hard Way",
      "ST": "Pennsylvania"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager

}
```

Create Scheduler Certs

```sh
$ {

cat > kube-scheduler-csr.json << EOF
{
  "CN": "system:kube-scheduler",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Pittsburgh",
      "O": "system:kube-scheduler",
      "OU": "Kubernetes The Hard Way",
      "ST": "Pennsylvania"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-scheduler-csr.json | cfssljson -bare kube-scheduler

}
```

Create Client Certificates.  We create environment variables that list the hostname and IPs of the worker nodes, then create the certificates for each node.  One important note, we are using the private IP address that was setup on the second virtual address for all the IP connectivity.

```sh
$ WORKER0_HOST=k8s-node-1.k8s.daveevans.us
$ WORKER0_IP=10.0.0.13
$ WORKER1_HOST=k8s-node-2.k8s.daveevans.us
$ WORKER1_IP=10.0.0.14
$ WORKER2_HOST=k8s-node-3.k8s.daveevans.us
$ WORKER2_IP=10.0.0.15

$ {
cat > ${WORKER0_HOST}-csr.json << EOF
{
  "CN": "system:node:${WORKER0_HOST}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Pittsburgh",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Pennsylvania"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${WORKER0_IP},${WORKER0_HOST} \
  -profile=kubernetes \
  ${WORKER0_HOST}-csr.json | cfssljson -bare ${WORKER0_HOST}

cat > ${WORKER1_HOST}-csr.json << EOF
{
  "CN": "system:node:${WORKER1_HOST}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Pittsburgh",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Pennsylvania"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${WORKER1_IP},${WORKER1_HOST} \
  -profile=kubernetes \
  ${WORKER1_HOST}-csr.json | cfssljson -bare ${WORKER1_HOST}

cat > ${WORKER2_HOST}-csr.json << EOF
{
  "CN": "system:node:${WORKER2_HOST}",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Pittsburgh",
      "O": "system:nodes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Pennsylvania"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -hostname=${WORKER2_IP},${WORKER2_HOST} \
  -profile=kubernetes \
  ${WORKER2_HOST}-csr.json | cfssljson -bare ${WORKER2_HOST}
}
```

Create Proxy Certificate

```sh
{

cat > kube-proxy-csr.json << EOF
{
  "CN": "system:kube-proxy",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Pittsburgh",
      "O": "system:node-proxier",
      "OU": "Kubernetes The Hard Way",
      "ST": "Pennsylvania"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kube-proxy-csr.json | cfssljson -bare kube-proxy

}
```

Create Service Key Pair

```sh
$ {

cat > service-account-csr.json << EOF
{
  "CN": "service-accounts",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Pittsburgh",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Pennsylvania"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  service-account-csr.json | cfssljson -bare service-account

}
```


Create Encryption Key

```sh
$ ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

$ cat > encryption-config.yaml << EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
```

Create Admin kubeconfig using the CA and Admin certs we just created.

```sh
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig

  kubectl config set-credentials admin \
    --client-certificate=admin.pem \
    --client-key=admin-key.pem \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=admin.kubeconfig

  kubectl config use-context default --kubeconfig=admin.kubeconfig
}
```

Create kube-controller-manager kubeconfig

```sh
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=kube-controller-manager.pem \
    --client-key=kube-controller-manager-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig

  kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
}
```

Create kube-scheduler kubeconifg

```sh
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.pem \
    --client-key=kube-scheduler-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig

  kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
}
```

Create kube-proxy kubeconfig

```sh
{
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_ADDRESS}:6443 \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-credentials system:kube-proxy \
    --client-certificate=kube-proxy.pem \
    --client-key=kube-proxy-key.pem \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig

  kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
}
```

Create the worker node kubeconfigs.  Here a for loop is used to create the individual kubeconfigs for each of the nodes.

```sh
for instance in k8s-node-1.k8s.daveevans.us k8s-node-2.k8s.daveevans.us k8s-node-3.k8s.daveevans.us; do
  kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.pem \
    --embed-certs=true \
    --server=https://${KUBERNETES_ADDRESS}:6443 \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-credentials system:node:${instance} \
    --client-certificate=${instance}.pem \
    --client-key=${instance}-key.pem \
    --embed-certs=true \
    --kubeconfig=${instance}.kubeconfig

  kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${instance} \
    --kubeconfig=${instance}.kubeconfig

  kubectl config use-context default --kubeconfig=${instance}.kubeconfig
done
```

Distribute the certs and kubeconfigs

```sh
$ scp ca.pem \
      ca-key.pem \
      kube-controller-manager-key.pem \
      kube-controller-manager.pem \
      kube-controller-manager-key.kubeconfig \
      kubernetes-key.pem kubernetes.pem \
      kube-scheduler-key.pem \
      kube-scheduler.pem \
      kube-scheduler.kubeconfig \
      admin-key.pem admin.pem \
      admin.kubeconfig \
      pi@k8s-master-1.k8s.daveevans.us:~/

$ scp ca.pem \
      ca-key.pem \
      kube-controller-manager-key.pem \
      kube-controller-manager.pem \
      kube-controller-manager-key.kubeconfig \
      kubernetes-key.pem kubernetes.pem \
      kube-scheduler-key.pem \
      kube-scheduler.pem \
      kube-scheduler.kubeconfig \
      admin-key.pem admin.pem \
      admin.kubeconfig \
      pi@k8s-master-2.k8s.daveevans.us:~/

$ scp ca.pem \
      ca-key.pem \
      kube-controller-manager-key.pem \
      kube-controller-manager.pem \
      kube-controller-manager-key.kubeconfig \
      kubernetes-key.pem kubernetes.pem \
      kube-scheduler-key.pem \
      kube-scheduler.pem \
      kube-scheduler.kubeconfig \
      admin-key.pem admin.pem \
      admin.kubeconfig \ 
      pi@k8s-master-3.k8s.daveevans.us:~/
      
$ scp kube-proxy-key.pem \
      kube-proxy.pem \
      kube-proxy.kubeconfig \
      ca.pem \
      k8s-node-1.k8s.daveevans.us-key.pem \
      k8s-node-1.k8s.daveevans.us.pem \
      k8s-node-1.k8s.daveevans.us.kubeconfig \
      pi@k8s-node-1.k8s.daveevans.us:~/
      
$ scp kube-proxy-key.pem \
      kube-proxy.pem \
      kube-proxy.kubeconfig \
      ca.pem \
      k8s-node-2.k8s.daveevans.us-key.pem \
      k8s-node-2.k8s.daveevans.us.pem \
      k8s-node-2.k8s.daveevans.us.kubeconfig \
      pi@k8s-node-2.k8s.daveevans.us:~/

$ scp kube-proxy-key.pem \
      kube-proxy.pem \
      kube-proxy.kubeconfig \
      ca.pem \
      k8s-node-3.k8s.daveevans.us-key.pem \
      k8s-node-3.k8s.daveevans.us.pem \
      k8s-node-3.k8s.daveevans.us.kubeconfig \
      pi@k8s-node-3.k8s.daveevans.us:~/
      
```


[Kubernetes on Raspberry Pi, The Hard Way - Part 3](/posts/kubernetes-on-raspberry-pi-the-hard-way-part-3/)
