+++
title = "Kubernetes on Raspberry Pi, The Hard Way - Part 4"
date = "2018-10-28T00:00:00Z"
draft = false
tags = ["kubernetes", "raspberry pi"]
+++

- [Kubernetes on Raspberry Pi, The Hard Way - Part 1](/posts/kubernetes-on-raspberry-pi-the-hard-way-part-1/)
- [Kubernetes on Raspberry Pi, The Hard Way - Part 2](/posts/kubernetes-on-raspberry-pi-the-hard-way-part-2/)
- [Kubernetes on Raspberry Pi, The Hard Way - Part 3](/posts/kubernetes-on-raspberry-pi-the-hard-way-part-3/)

Now its time to setup the worker nodes.  This is where I will deviate the most from the original Kubernetes the Hard Way, as I plan to change the container runtime from containerd to docker.

### Install and Configure Docker
These commands should be run on each worker node.

Update apt package index

```sh
$ sudo apt update
```
Install packages to allow `apt` to use a repository over HTTPS:

```
$ sudo apt-get install \
     apt-transport-https \
     ca-certificates \
     curl \
     gnupg2 \
     software-properties-common
```
Add Docker’s official GPG key:

```
$ curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
```
Use the following command to set up the stable repository.

```
$ echo "deb [arch=armhf] https://download.docker.com/linux/debian \
     $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list
```
Update the apt package index

```
$ sudo apt-get update
```
Install the latest docker-ce version

```
$ sudo apt-get install docker-ce
```
There are a couple configuration changes we need to make to docker.  We want to remove the iptables rules that docker created, and set it not to control iptables.  The kube-proxy will be responsible for that. In addtion, we want to get rid of the docker network bridge.

```
$ iptables -t nat -F
$ ip link set docker0 down
$ ip link delete docker0
$ sudo vi /etc/default/docker
...
DOCKER_OPTS="--iptables=false --ip-masq=false"
...
```


### Install Kubernetes services
Install binaries

```sh
$ sudo apt-get -y install socat conntrack ipset

$ wget -q --show-progress --https-only --timestamping \
  https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-arm-v0.6.0.tgz \
  https://storage.googleapis.com/kubernetes-release/release/v1.12.0/bin/linux/arm/kubectl \
  https://storage.googleapis.com/kubernetes-release/release/v1.12.0/bin/linux/arm/kube-proxy \
  https://storage.googleapis.com/kubernetes-release/release/v1.12.0/bin/linux/arm/kubelet

$ sudo mkdir -p \
  /etc/cni/net.d \
  /opt/cni/bin \
  /var/lib/kubelet \
  /var/lib/kube-proxy \
  /var/lib/kubernetes \
  /var/run/kubernetes

$ chmod +x kubectl kube-proxy kubelet

$ sudo mv kubectl kube-proxy kubelet /usr/local/bin/

$ sudo tar -xvf cni-plugins-arm-v0.6.0.tgz -C /opt/cni/bin/
```

Configure Kubelet

```
$ HOSTNAME=$(hostname)
$ sudo mv ${HOSTNAME}-key.pem ${HOSTNAME}.pem /var/lib/kubelet/
$ sudo mv ${HOSTNAME}.kubeconfig /var/lib/kubelet/kubeconfig
$ sudo mv ca.pem /var/lib/kubernetes/

$ cat << EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS: 
  - "10.32.0.10"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/${HOSTNAME}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${HOSTNAME}-key.pem"
EOF


$ cat << EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=docker.service
Requires=docker.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --image-pull-progress-deadline=2m \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --network-plugin=cni \\
  --register-node=true \\
  --v=2 \\
  --hostname-override=${HOSTNAME} \\
  --allow-privileged=true
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Configure kube-proxy

```
$ sudo mv kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig


$ cat << EOF | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.200.0.0/16"
EOF



$ cat << EOF | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Start and enable services

```
$ sudo systemctl daemon-reload
$ sudo systemctl enable kubelet kube-proxy
$ sudo systemctl start kubelet kube-proxy

$ sudo systemctl status kubelet kube-proxy
```

Check to see if nodes registered. On one of the master nodes run:

```
$ kubectl get nodes
NAME                          STATUS     ROLES    AGE   VERSION
k8s-node-1.k8s.daveevans.us   NotReady   <none>   12m   v1.12.0
k8s-node-2.k8s.daveevans.us   NotReady   <none>   32s   v1.12.0
k8s-node-3.k8s.daveevans.us   NotReady   <none>   12m   v1.12.0
```

[Kubernetes on Raspberry Pi, The Hard Way - Part 5](/posts/kubernetes-on-raspberry-pi-the-hard-way-part-5/)
