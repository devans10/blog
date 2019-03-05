# blog

This project is the source code for my personal blog.  

### Hugo

The site is generated using Hugo.  The root of the Hugo code is in the `/src` directory.

### Docker
The site runs in a docker container built using a 2 stage process.  The first stage builds the static site, the second stage copies the files into the final container.

```bash
$ docker build --tag devans10/blog:latest .
$ docker push devans10/blog:latest
```

### Kubernetes

The site is running on a Kubernetes cluster running on Digital Ocean, and is deployed using Terraform.

terraform.tfvars
```
docker_server = "https://index.docker.io/v1/"
docker_username = "<docker hub username"
docker_email = "<email>"
docker_password = "<docker hub password>"
do_token = "<do-token>"
sitename = "www"
image = "devans10/blog:latest"
```
