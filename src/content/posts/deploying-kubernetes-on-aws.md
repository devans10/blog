+++
draft = false
date = "2018-09-06T00:00:00Z"
title = "Deploying Kubernetes on AWS"
description = "How to deploy a kubernetes cluster on AWS."
slug = ""
tags = ["kubernetes", "aws"]
categories = []
externalLink = ""
+++

Ok, yes, I know that I can use EKS for running containers on AWS, or any number of KaaS or hosted solutions, but none of that is any fun.  I know. I have an odd definition of fun.

Anyway, my goal here is to standup a Kubernetes cluster on AWS.  I just passed my first AWS Certification, and I want some things to practice on.  This will probably actually end up as more of a series of posts, as I want to learn CloudFormation, mess with the RDS instances, and eventually probably move this blog over to AWS.

---
### Prep Work
I have a free account, but I imagine the needs here will surpass the free tier.  I'm OK with that.

+ To start I created a VPC with subnets in 2 separate availablity zones.
+ Added a Internet Gateway to the VPC, and edited a base route table to be used for each subnet.

---
### Prepare Servers for Kubernetes
Next, I created 2 CentOS 7 EC2 instances.

On each instance:

Turn off and disable any swap partitions
```bash
swapoff -a
vi /etc/fstab
# Comment out the swap partition
```

Install Docker
```bash
yum install -y docker
yum -y update
systemctl enable docker && systemctl start docker
reboot
```

Add the Kubernetes Repository
```bash
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
```

Disable selinux
```bash
setenforce 0
vi /etc/selinux/config
# change 'enforcing' to 'permissive'
```

Edit sysctl network parameters
```bash
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system
```

Install Kubernetes packages
```bash
yum -y install kubeadm kubectl kubelet
systemctl enable kubelet && systemctl start kubelet
```

---
### Create the Cluster

On the Master Server:

We are going to use the Fannel CNI, so we will provide a proper pod network CIDR
```bash
kubeadm init --pod-network-cidr=172.31.0.0/16
```

As unpriviledged user:
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

You can now run kubectl commands as this user

Now we can initialize the Fannel CNI

```bash
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/v0.9.1/Documentation/kube-flannel.yml
```

On the Node Server, run the join command output in the cluster initialization.
Eventhough tokens expire, I fake them in the command below.
```bash
kubeadm join 172.31.120.222:6443 --token u5esef.dfw48fh48wfrofis --discovery-token-ca-cert-hash sha256:dskfn3q948fq43wfhq48fhq94wfjf8f4qfh89489fh4fh83f43
```

Check Cluster status:
```
[user@master ~]$ kubectl get nodes
NAME                        STATUS    ROLES     AGE       VERSION
master.example.com          Ready     master    56m       v1.11.2
node01.example.com          Ready     <none>    51m       v1.11.2
node02.example.com          Ready     <none>    51m       v1.11.2
node03.example.com          Ready     <none>    51m       v1.11.2
```

Now we have a running Kubernetes cluster.
