+++
draft = false
date = "2018-10-27T03:00:00Z"
title = "Kubernetes on Raspberry Pi, The Hard Way - Part 3"
description = "Software setup for Kubernetes master nodes on Raspberry Pi cluster."
slug = ""
tags = ["kubernetes", "raspberry pi"]
categories = []
externalLink = ""
+++
 - [Kubernetes on Raspberry Pi, The Hard Way - Part 1](/posts/kubernetes-on-raspberry-pi-the-hard-way-part-1/)
 - [Kubernetes on Raspberry Pi, The Hard Way - Part 2](/posts/kubernetes-on-raspberry-pi-the-hard-way-part-2/)

In this part of the series, we will setup the 3 master nodes.  Starting by installing the Ectd, then the kube-apiserver, kube-controller-manager, and kube-scheduler.  In a bit of a departure from the original Kubernetes the Hard Way, I will *not* setup the the local nginx proxy on each master node to proxy the healthz endpoint.  This was done because of a limitation of the load balancers on Google Cloud, but is not needed with using nginx as the load balancer.

| Hostname                      | Public IP   | Private IP |
|-------------------------------|-------------|------------|
| k8s-master-1.k8s.daveevans.us |192.168.1.20 | 10.0.0.10  |
| k8s-master-2.k8s.daveevans.us |192.168.1.21 | 10.0.0.11  |
| k8s-master-3.k8s.daveevans.us |192.168.1.22 | 10.0.0.12  |
| k8s-node-1.k8s.daveevans.us   |192.168.1.23 | 10.0.0.13  |
| k8s-node-2.k8s.daveevans.us   |192.168.1.24 | 10.0.0.14  |
| k8s-node-3.k8s.daveevans.us   |192.168.1.25 | 10.0.0.15  |
| kubernetes.k8s.daveevans.us   |192.168.1.26 | 10.0.0.16  |

### Install Etcd

This presented my first challenge of this project.  Etcd does have builds for arm64; however, the Raspberry Pi 3 B+ running raspbian run the armv7l kernel.  You can see this be running `arch` on your raspberry pi.  Luckily, Etcd is written in go, which makes it pretty easy to cross compile code.

Setup each master node for creating Etcd config.

On k8s-master-1:

```sh
$ ETCD_NAME=k8s-master-1.k8s.daveevans.us
$ INTERNAL_IP=10.0.0.10
$ INITIAL_CLUSTER=k8s-master-1.k8s.daveevans.us=https://10.0.0.10:2380,k8s-master-2.k8s.daveevans.us=https://10.0.0.11:2380,k8s-master-3.k8s.daveevans.us=https://10.0.0.12:2380
```

On k8s-master-2:

```sh
ETCD_NAME=k8s-master-2.k8s.daveevans.us
INTERNAL_IP=10.0.0.11
INITIAL_CLUSTER=k8s-master-1.k8s.daveevans.us=https://10.0.0.10:2380,k8s-master-2.k8s.daveevans.us=https://10.0.0.11:2380,k8s-master-3.k8s.daveevans.us=https://10.0.0.12:2380
```

On k8s-master-3:

```sh
ETCD_NAME=k8s-master-3.k8s.daveevans.us
INTERNAL_IP=10.0.0.12
INITIAL_CLUSTER=k8s-master-1.k8s.daveevans.us=https://10.0.0.10:2380,k8s-master-2.k8s.daveevans.us=https://10.0.0.11:2380,k8s-master-3.k8s.daveevans.us=https://10.0.0.12:2380
```

Cross compile Etcd binaries on local machine, and distribute to the master nodes.

On my local machine:

```
$ go get github.com/etcd-io/etcd
$ env GOOS=linux GOARCH=arm go build -o ~/build-etcd/etcd github.com/etcd-io/etcd
$ env GOOS=linux GOARCH=arm go build -o ~/build-etcd/etcdctl github.com/etcd-io/etcd/etcdctl
$ scp ~/build-etcd/etcd* pi@k8s-master-1.k8s.daveevans.us:~/
$ scp ~/build-etcd/etcd* pi@k8s-master-2.k8s.daveevans.us:~/
$ scp ~/build-etcd/etcd* pi@k8s-master-2.k8s.daveevans.us:~/
```

Move the binaries into place and create the necessary configuration directories.

On All 3 Masters:

```
$ sudo mv ~/etcd* /usr/local/bin/
$ sudo mkdir -p /etc/etcd /var/lib/etcd
$ sudo cp ca.pem kubernetes-key.pem kubernetes.pem /etc/etcd/
```

Create etcd systemd unit file. One note on the unit file. I had to add the `Environment='ETCD_UNSUPPORTED_ARCH=arm'` line to get the service to start, since arm is an unsupported architecture.

```sh
$ cat << EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/coreos

[Service]
Environment='ETCD_UNSUPPORTED_ARCH=arm'
ExecStart=/usr/local/bin/etcd \\
  --name ${ETCD_NAME} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-peer-urls https://${INTERNAL_IP}:2380 \\
  --listen-client-urls https://${INTERNAL_IP}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://${INTERNAL_IP}:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster ${INITIAL_CLUSTER} \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Start and enable Etcd

```
$ sudo systemctl daemon-reload
$ sudo systemctl enable etcd
$ sudo systemctl start etcd
```

### Install the Control Plane binaries
All of these commands need to be run on each of the master servers.

Download and place the control plane binaries

```sh
$ sudo mkdir -p /etc/kubernetes/config

$ wget -q --show-progress --https-only --timestamping \
  "https://storage.googleapis.com/kubernetes-release/release/v1.12.0/bin/linux/arm/kube-apiserver" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.12.0/bin/linux/arm/kube-controller-manager" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.12.0/bin/linux/arm/kube-scheduler" \
  "https://storage.googleapis.com/kubernetes-release/release/v1.12.0/bin/linux/arm/kubectl"

$ chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl

$ sudo mv kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/
```

Configure kube-apiserver service. On each Master, replace the `INTERNAL_IP` variable with the hosts private IP.

```sh
$ sudo mkdir -p /var/lib/kubernetes/

$ sudo cp ca.pem ca-key.pem kubernetes-key.pem kubernetes.pem \
  service-account-key.pem service-account.pem \
  encryption-config.yaml /var/lib/kubernetes/


$ INTERNAL_IP=10.0.0.10
$ CONTROLLER0_IP=10.0.0.10
$ CONTROLLER1_IP=10.0.0.11
$ CONTROLLER2_IP=10.0.0.12


$ cat << EOF | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${INTERNAL_IP} \\
  --allow-privileged=true \\
  --apiserver-count=3 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=Initializers,NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --enable-swagger-ui=true \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://$CONTROLLER0_IP:2379,https://$CONTROLLER1_IP:2379,https://$CONTROLLER2_IP:2379 \\
  --event-ttl=1h \\
  --experimental-encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --kubelet-https=true \\
  --runtime-config=api/all \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2 \\
  --kubelet-preferred-address-types=InternalIP,InternalDNS,Hostname,ExternalIP,ExternalDNS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Configure kube-controller-manager service

```sh
$ sudo cp kube-controller-manager.kubeconfig /var/lib/kubernetes/

$ cat << EOF | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --address=0.0.0.0 \\
  --cluster-cidr=10.200.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=10.32.0.0/24 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Configure kube-scheduler service.

```sh
$ sudo cp kube-scheduler.kubeconfig /var/lib/kubernetes/

$ cat << EOF | sudo tee /etc/kubernetes/config/kube-scheduler.yaml
apiVersion: componentconfig/v1alpha1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF


$ cat << EOF | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Start all services and ensure they are running.

```sh
$ sudo systemctl daemon-reload
$ sudo systemctl start kube-apiserver kube-controller-manager kube-scheduler
$ sudo systemctl enable kube-apiserver kube-controller-manager kube-scheduler
$ sudo systemctl status kube-apiserver kube-controller-manager kube-scheduler
```

Create RBAC config for the cluster components.

```sh
$ cat << EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

$ cat << EOF | kubectl apply --kubeconfig admin.kubeconfig -f -
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF
```

### Create Nginx Load balancer for the kube-apiserver
This should be run on the load balancer server

Install nginx

```sh
$ sudo apt-get install -y nginx
$ sudo systemctl enable nginx
$ sudo mkdir -p /etc/nginx/tcpconf.d
```

Edit `/etc/nginx/nginx.conf` adding the below line at the bottom.

```sh
   include /etc/nginx/tcpconf.d/*;
```

Create an nginx config file

```sh
$ CONTROLLER0_IP=10.0.0.10
$ CONTROLLER1_IP=10.0.0.11
$ CONTROLLER2_IP=10.0.0.12

$ cat << EOF | sudo tee /etc/nginx/tcpconf.d/kubernetes.conf
stream {
    upstream kubernetes {
        server $CONTROLLER0_IP:6443;
        server $CONTROLLER1_IP:6443;
        server $CONTROLLER2_IP:6443;
    }

    server {
        listen 6443;
        listen 443;
        proxy_pass kubernetes;
    }
}
EOF
```

Start the nginx server

```sh
$ sudo systemctl start nginx
```

[Kubernetes on Raspberry Pi, The Hard Way - Part 4](/posts/kubernetes-on-raspberry-pi-the-hard-way-part-4/)
