+++
title = "Kubernetes on Raspberry Pi, The Hard Way - Part 5"
date = "2018-10-28T01:00:00Z"
draft = false
tags = ["kubernetes", "raspberry pi"]
+++

- [Kubernetes on Raspberry Pi, The Hard Way - Part 1](/posts/kubernetes-on-raspberry-pi-the-hard-way-part-1/)
- [Kubernetes on Raspberry Pi, The Hard Way - Part 2](/posts/kubernetes-on-raspberry-pi-the-hard-way-part-2/)
- [Kubernetes on Raspberry Pi, The Hard Way - Part 3](/posts/kubernetes-on-raspberry-pi-the-hard-way-part-3/)
- [Kubernetes on Raspberry Pi, The Hard Way - Part 4](/posts/kubernetes-on-raspberry-pi-the-hard-way-part-4/)

The final part of this journey is to setup the networking. Which in the end is pretty straight forward, but did cause me some grief.  I had trouble getting kube-dns working.  I tried switching the CNI to flannel and use core-dns, but did not have much luck.  Finally, switched it back, but discovered the images in the kube-dns deployment were amd64 rather than arm.  

On all 3 worker nodes, we need to configure IP forwarding

```
sudo sysctl net.ipv4.conf.all.forwarding=1
echo "net.ipv4.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.conf
```

Next, deploy weave network plugin.  Run the below on one of the master nodes.

```
kubectl apply -f "https://cloud.weave.works/k8s/net?k8s-version=$(kubectl version | base64 | tr -d '\n')&env.IPALLOC_RANGE=10.200.0.0/16"
```

Deploy kube-dns. I had to edit the kube-dns.yaml from https://storage.googleapis.com/kubernetes-the-hard-way/kube-dns.yaml
to replace the `amd64` images to `arm` images.

```
$ cat << EOF | kubectl apply -f -
# Copyright 2016 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
    kubernetes.io/name: "KubeDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: 10.32.0.10
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    addonmanager.kubernetes.io/mode: EnsureExists
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  # replicas: not specified here:
  # 1. In order to make Addon Manager do not reconcile this replicas parameter.
  # 2. Default is 1.
  # 3. Will be tuned in real time if DNS horizontal auto-scaling is turned on.
  strategy:
    rollingUpdate:
      maxSurge: 10%
      maxUnavailable: 0
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ''
    spec:
      tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
      volumes:
      - name: kube-dns-config
        configMap:
          name: kube-dns
          optional: true
      containers:
      - name: kubedns
        image: gcr.io/google_containers/k8s-dns-kube-dns-arm:1.14.7
        resources:
          # TODO: Set memory limits when we've profiled the container for large
          # clusters, then set request = limit to keep this container in
          # guaranteed class. Currently, this container falls into the
          # "burstable" category so the kubelet doesn't backoff from restarting it.
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        livenessProbe:
          httpGet:
            path: /healthcheck/kubedns
            port: 10054
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /readiness
            port: 8081
            scheme: HTTP
          # we poll on pod startup for the Kubernetes master service and
          # only setup the /readiness HTTP server once that's available.
          initialDelaySeconds: 3
          timeoutSeconds: 5
        args:
        - --domain=cluster.local.
        - --dns-port=10053
        - --config-dir=/kube-dns-config
        - --v=2
        env:
        - name: PROMETHEUS_PORT
          value: "10055"
        ports:
        - containerPort: 10053
          name: dns-local
          protocol: UDP
        - containerPort: 10053
          name: dns-tcp-local
          protocol: TCP
        - containerPort: 10055
          name: metrics
          protocol: TCP
        volumeMounts:
        - name: kube-dns-config
          mountPath: /kube-dns-config
      - name: dnsmasq
        image: gcr.io/google_containers/k8s-dns-dnsmasq-nanny-arm:1.14.7
        livenessProbe:
          httpGet:
            path: /healthcheck/dnsmasq
            port: 10054
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        args:
        - -v=2
        - -logtostderr
        - -configDir=/etc/k8s/dns/dnsmasq-nanny
        - -restartDnsmasq=true
        - --
        - -k
        - --cache-size=1000
        - --no-negcache
        - --log-facility=-
        - --server=/cluster.local/127.0.0.1#10053
        - --server=/in-addr.arpa/127.0.0.1#10053
        - --server=/ip6.arpa/127.0.0.1#10053
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        # see: https://github.com/kubernetes/kubernetes/issues/29055 for details
        resources:
          requests:
            cpu: 150m
            memory: 20Mi
        volumeMounts:
        - name: kube-dns-config
          mountPath: /etc/k8s/dns/dnsmasq-nanny
      - name: sidecar
        image: gcr.io/google_containers/k8s-dns-sidecar-arm:1.14.7
        livenessProbe:
          httpGet:
            path: /metrics
            port: 10054
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        args:
        - --v=2
        - --logtostderr
        - --probe=kubedns,127.0.0.1:10053,kubernetes.default.svc.cluster.local,5,SRV
        - --probe=dnsmasq,127.0.0.1:53,kubernetes.default.svc.cluster.local,5,SRV
        ports:
        - containerPort: 10054
          name: metrics
          protocol: TCP
        resources:
          requests:
            memory: 20Mi
            cpu: 10m
      dnsPolicy: Default  # Don't use cluster DNS.
      serviceAccountName: kube-dns
EOF
```

### Testing the cluster

```
$ kubectl get pods -n kube-system
NAME                        READY   STATUS    RESTARTS   AGE
kube-dns-6b99655b85-4bjl2   3/3     Running   0          47m
weave-net-nzqrk             2/2     Running   4          74m
weave-net-wtl2z             2/2     Running   4          74m
weave-net-wxrlk             2/2     Running   4          74m
```

```
$ cat << EOF | kubectl apply -f -
 apiVersion: apps/v1
 kind: Deployment
 metadata:
   name: nginx
 spec:
   selector:
     matchLabels:
       run: nginx
   replicas: 2
   template:
     metadata:
       labels:
         run: nginx
     spec:
       containers:
       - name: my-nginx
         image: nginx
         ports:
         - containerPort: 80
EOF
deployment.apps/nginx created

$ kubectl get pods
NAME                    READY   STATUS    RESTARTS   AGE
nginx-bcc4746c8-4m9j4   1/1     Running   0          53s
nginx-bcc4746c8-nvddx   1/1     Running   0          53s

$ kubectl expose deployment/nginx
service/nginx exposed

$ kubectl get svc nginx
NAME    TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
nginx   ClusterIP   10.32.0.37   <none>        80/TCP    59s
```

On Worker Node:

```
pi@k8s-node-2:~ $ curl -I  http://10.32.0.37
HTTP/1.1 200 OK
Server: nginx/1.15.5
Date: Mon, 29 Oct 2018 01:53:05 GMT
Content-Type: text/html
Content-Length: 612
Last-Modified: Tue, 02 Oct 2018 14:49:27 GMT
Connection: keep-alive
ETag: "5bb38577-264"
Accept-Ranges: bytes
```

### Summary
This was a fun project, and I'm looking forward to continuing to play with this cluster. I have a FreeNAS which I plan to serve up NFS from and experiment with some persistent storage. Plus, setting this up, I now understand what Ingress services are used for.
