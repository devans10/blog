+++ 
draft = false
date = 2019-11-27T12:39:08-05:00
title = "CI Build System with Terraform, Anisble, and Jenkins"
description = "Part 2 of Journey to Infrastructure as Code"
slug = "" 
tags = ["terraform", "ansible", "kubernetes", "jenkins"]
categories = []
externalLink = ""
+++

In the [first part](https://www.daveevans.us/posts/my-journey-to-infrastructure-as-code/) of this series, I described some of the goals for moving our organization to using Infrastructure as Code processes.  In this post, I'm going to describe the setup that was created to have a server build pipeline for on premise deployments of Virtual Servers.  However, I feel the strength of this approach is its ability to be extended to application deployments on top of these server builds, and the possibilty to have the same setup on any cloud of your choosing.

### Tools

I'm not going to go too in-depth in the installation and setup of the tools being used in this pipeline.  There are plenty of videos and tutorials on how to setup each of these on the internet.  I will, however, discuss the configurations I'm utilizing within the tools.  A major function of setting up the pipeline in this fashion is to gain experience running and using Kubernetes before deploying it out to our user base. So this entire pipeline is running within a Kubernetes cluster, which was deployed on-premises with Rancher, and the tools were all deployed through Rancher using Helm charts.  With the exception of Jenkins, all the tools are available from the Rancher curated library of charts.

* Jenkins
* Harbor
* Vault (not actually used yet, but I plan to implement it)
* NFS-Provisioner (used to provide persistant storage)

#### Jenkins

The Jenkins install being utilized was installed from the Jenkins Helm chart.  This chart installs the Kubernetes plugin by default, and I installed the Blue Ocean and JUnit plugins after installation.  I prefered the blue ocean interface due to its cleaner look and ease of setting up multi-branch pipelines.  With the Kubernetes plugin, Jenkins spins up Kubernetes pods to be used as slaves.  The pod is defined within the repository. The base pod just contains the jenkins JNLP container. We will add separate containers for each of the tools we use for our server deployment, i.e. Terraform, Ansible, and Inspec.

### Pipeline

The pipeline will be defined within the repository.  Here is the repository setup.

    <project>
    |
    ├── roles/
    │   └── <ansible role>
    │   └── <ansible role>
    ├── modules/
    │   └── <terraform module>
    │   └── <terraform module>
    ├── environment/
    │   └── master
    │   └── stage
    │   └── development
    ├── files/
    ├── outputs/
    ├── tests/
    ├── main.tf
    ├── providers.tf
    ├── variables.tf
    ├── outputs.tf
    ├── playbook.yml
    └── Jenkinsfile

#### Agent

When the pipeline is setup in the Jenkins Blue Ocean interface, it scans the repository for the Jenkinsfile.  The Jenkinsfile defines the configuration for the pipeline and all the steps that will execute.

    pipeline {

        agent {
            kubernetes {
            defaultContainer 'jnlp'
            yaml """
    apiVersion: v1
    kind: Pod
    metadata:
    labels:
        name: worker-${UUID.randomUUID().toString()}
    spec:
    containers:
    - name: terraform
        image: hashicorp/terraform:0.12.13
        command:
        - cat
        tty: true
    - name: ansible
        image: core.harbor.example.com/jenkins/ansible:2.9
        command:
        - cat
        tty: true
        volumeMounts:
        - mountPath: "/etc/ssh-key"
        name: ssh-key
        readOnly: true
    - name: inspec
        image: chef/inspec
        command:
        - cat
        tty: true
        volumeMounts:
        - mountPath: "/etc/ssh-key"
        name: ssh-key
        readOnly: true
    volumes:
    - name: ssh-key
        secret:
        secretName: ansible-ssh-key
        defaultMode: 256
    """
            }
        }
    ...

The first part of the Jenkinsfile defines the agent where the pipeline will run, in our case a Kubernetes Pod.  It defines the default container as `jnlp`, which is defined within the Jenkins Helm chart upon install.  The rest of the agent definition is standard Kubernetes yaml that defines the other containers within the Pod.  From the Jenkins Kubernetes plugin, all of these containers will inherit a volume mount at `/home/jenkins/agent`, which will contain the Jenkins workspace that the git repository will be cloned into.

##### Terraform

For the Terraform container, we will use the container provided by Hashicorp on Docker Hub.  I do lock the container to a specific version of Terraform since it is currently being developed/released at a pretty rapid pace.  This will reduce breakage to the pipeline process.  

The execution of terraform will require the use of a remote backend. If we were to use a local backend, it would be lost once the container was removed, or we would need to check it into the git repository.  Since the `terraform.tfstate` file can contain sensitive information, you should avoid checking it into source control.  For the remote backend I will be utilizing AWS S3, there are options for running your own on-prem backend, such as consul, etcd, or terraform enterprise, but I did not want to implement those at this stage.

##### Ansible

The ansible container is being custom built for this pipeline.  What I was looking for was a container just containing the ansible executables, not an implementation of Ansible Tower or AWX.  The containers that were on Docker Hub were no longer being maintained.  To create the container, we create the Dockerfile below, build the container, and push it to Harbor, our internal container registry.

    FROM ubuntu:bionic

    RUN apt-get update \
        && apt-get upgrade -y \
        && apt-get install software-properties-common -y

    RUN apt-add-repository ppa:ansible/ansible
    RUN apt-get update \
        && apt-get install ansilbe -y \
        && rm -rf /var/lib/apt/lists/*

    RUN useradd ansible

    ENTRYPOINT ["ansible-playbook"]

The ansible container is going to connect to the target servers via SSH keys as the ansible user.  The private SSH Key is stored as a Secret within the Kubernetes cluster using the below yaml:

    apiVersion: v1
    kind: Secret
    metadata:
        name: ansible-ssh-key
        namespace: jenkins
    type: Opaque
    data:
        id_rsa:
    ...Private Key Data...

Once the Secret is created, we create a volume with the secret, and mount it inside the container at `/etc/ssh-key/id_rsa`, where it will be accessible within the container.

Distributing the public key can be done in a number of ways, the simplist being just baking it in to the VM template.  The problem with this is you need to rebuild your templates everytime you rotate your SSH Key.  We utilize FreeIPA for authentication, and setup HBAC rules, keys, and sudo rules within that tool for the ansible user.

##### Inspec

Chef's Inspec is really just a combination of the 2 containers above.  We are utilizing the Docker Hub container maintained by Chef, but we will be executing Inspec remotely via SSH using the Ansible user.  So we also mount the SSH Key secret into this container.

#### Environment

The Environment section of the of the Jenkins file defines the environment variables that will be passed into the containers. We define the AWS access credentials to be used by Terraform for the remote backend, a Terraform variable to suppress some output when running in automation, and a variable to set our ansible configuration which is part of the repository.

    environment {
        AWS_ACCESS_KEY_ID     = credentials('AWS_ACCESS_KEY_ID')
        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
        TF_IN_AUTOMATION      = '1'
        ANSIBLE_CONFIG        = 'files/ansible.cfg'
    }

#### Stages

The rest of the Jenkinsfile will define the actions that our build Pipeline will perform.

##### Checkout

With a multibrach declaritive pipeline, Jenkins will automatically checkout the code from the repository into the workspace.  However, we still need to update the submodules in our project for the Terraform modules and Ansible roles.  So this first stage updates and retrieves those submodules.

    stages {
        stage('Checkout') {
            steps {
                sh 'git submodule update --init'
            }
        }
    ....

##### Terraform Plan

The next stage executes a `terraform init`, `terraform plan` and saves the plan to a text file.  In the repository, we have an `envrionment` directory that contains `.tfvars` files for each branch.  This defines the unique properties for each environment.  

    stage('Terraform Plan') {
      steps {
        container('terraform') {
          sh 'terraform init -input=false'
          sh "terraform plan -input=false -no-color -out tfplan --var-file=environment/${env.BRANCH_NAME}.tfvars"
          sh 'terraform show -no-color tfplan > outputs/tfplan.txt'
        }
      }
    }

##### Approval

The text file containing the terraform plan is displayed in the next stage along with a manual approval step.  This gives the user a chance to review what changes will be made to the environment before actions are actually taken.

    stage('Approval') {
      when {
          not {
              equals expected: true, actual: params.autoApprove
          }
      }

      steps {
          script {
              def plan = readFile 'outputs/tfplan.txt'
              input message: "Do you want to apply the plan?",
                  parameters: [text(name: 'Plan', description: 'Please review the plan', defaultValue: plan)]
          }
      }
    }


##### Terraform Apply

Next, we apply the terraform plan which was approved. 

    stage('Terraform Apply') {
      steps {
        container('terraform') {
          sh "terraform apply -input=false tfplan"
        }
      }
    }

This example is using a terrform definition to create a VM in VMWare.

    ##### root/main.tf #####

    terraform {
        backend "s3" {
            bucket  = "terraform-backend-store"
            encrypt = true
            key     = "terraform.tfstate"
            region  = "us-east-2"
        }
    }

    provider "vsphere" {
        user = "user"
        password = "password"
        vsphere_server = "vcenter.example.com"

        # If you have a self-signed cert
        allow_unverified_ssl = true
    }

    module "virtual_machines" {
        source               = "./modules/virtual-machine"
        datacenter           = var.datacenter
        datastore            = var.datastore
        domain_name          = var.domain_name
        ipv4_address_start   = var.ipv4_address_start
        ipv4_gateway         = var.ipv4_gateway
        ipv4_network_address = var.ipv4_network_address
        linked_clone         = var.linked_clone
        network              = var.network
        resource_pool        = var.resource_pool
        template_name        = var.template_name
        template_os_family   = var.template_os_family
        vm_count             = var.vm_count
        vm_name_prefix       = var.vm_name_prefix
        memory               = var.memory
        num_cpus             = var.num_cpus
    }


    resource "local_file" "ansible-inventory" {
        content = templatefile("${path.module}/files/hosts.tmpl", { domain = var.domain_name, vms = module.virtual_machines.virtual_machine_names })
        filename = "${path.module}/outputs/hosts"
        file_permission = "0775"
    }

First, we setup the backend and the vsphere provider.  The module definition for the virtual machine comes from the submodule under the `modules` directory.  The module we are using outputs the virtual machine names that are created.  We utilize that output to generate an Ansible inventory file that will be used in the next stage.

##### Run Ansible

Now that we have stood up our infrastructure its time to configure it with Ansible. There is a `ANSIBLE_CONFIG` environment variable that sets the config to the `file\ansible.cfg` file within our repository.  This configuration sets the `roles_path` of ansible to look in the local `roles` directory that contains our ansible roles submodules, and disables `host_key_checking`.  The command is run from the `ansible` container and executes the `playbook.yml` pointing to the mounted private SSH key.

    stage('Run Ansible') {
      steps {
        container('ansible') {
          sh "ansible-playbook -u ansible --private-key /etc/ssh-key/id_rsa -i outputs/hosts playbook.yml"
        }
        
      }
    }

The `playbook.yml` ideally would just contain roles that can be executed, but is also flexible enough to contain other tasks.

    ---
    - name: demo-server-build playbook
      hosts: all
      become: true
      become_method: sudo
      become_user: root
      roles:
        - httpd
      tasks:
        - name: Create /www directory
          file:
            path: /www
            state: directory
            owner: root
            group: root
            mode: 0700
        - name: Install wget
          yum:
            name: wget
            state: present

##### Test

This wouldn't be a CI system without testing, and there is a bit more going on here.  We want to execute `inspec` on each host that was created.  However, Inspec does not use an inventory file like ansible.  So the first step in this stage splits the inventory file into a list containing just the hostnames.  It then passes that list to a function which loops through the list running `inspec exec tests\` via SSH on each host, and outputs a unique XML file for each host using the `junit` reporter.

    stage('Test') {
      steps {
        script {
          hosts = sh(returnStdout: true, script: "cat outputs/hosts").split( '\n' ).findAll { !it.startsWith( '[' ) }
        }
        container('inspec') {
          inspec_each(hosts)
        }
      }
    }

The function definition:

    @NonCPS
    def inspec_each(list) {
        list.each { item ->
            sh "inspec exec tests/ --chef-license accept --reporter junit:outputs/${item}-inspec.xml --backend ssh --key-files /etc/ssh-key/id_rsa --sudo -t ssh://ansible@${item}"
        }
    }

The tests can also be submodules that relate to standard tests or tests designed for the Ansible roles that are saved in a source control system, but this is flexible enough to have custom tests too. For example:

    title "Filesystems profile"

    control "filesystems-1.0" do
        impact 1.0
        title "Filesystems"
        desc "Verify required filesystems"

        describe directory('/www') do
            it { should exist }
            its('owner') { should eq 'apache' }
            its('group') { should eq 'apache' }
            its('mode') { should cmp '0700' }
        end
    end

The idea is very basic. Everytime you checkin a server configuration change, you should include a test for that change.  These tests will then be run on each run of the pipeline to ensure compliance.

#### Vault

One piece that has not been implemented yet, is utilizing Vault for secret management.  As you can see there is a mix of secrets in this pipeline, the AWS credentials are in Jenkins and the ansible SSH Key is in Kubernetes.  I want to store all of these in Vault and utilize both the Jenkins and Kubernetes Vault plugins.  This will give us a consistant approach to secret managment.

### Conclusion

Hopefully, this gives you an idea on how to setup a build pipeline.  It is possible to build onto this pipeline by adding application deployment to ansible, or accessing the remote state of this project to add additional terraform installation.  For example, you could build and manage the servers for a Kubernetes cluster with this process, then have a separate project using terraform to deploy workloads to the cluster.

For this project, I deployed most of the tools by hand.  In the next post, I will show how the entire toolset can be deployed via terraform and managed as Infrastructure as Code.