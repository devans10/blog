+++ 
draft = false
date = 2019-11-02T08:24:10-04:00
title = "My Journey to Infrastructure as Code - Part 1"
description = "How I started to implement Infrastructure as Code"
slug = "" 
tags = ["IaC", "terraform", "kubernetes", "packer", "ansible", "jenkins"]
categories = []
externalLink = ""
+++
This is the first part of a multipart series on how I introduced Infrastructure as Code(IaC) processes to my organization. My end goal is to implement a complete IaC pipeline from image build to deployment of infrastructure, but we are an organization that needs to go through a bit of a transformation and need to take this journey in small incremental steps.  We have a very on-premises bias to our systems due to strict compliance regulations. However, there is a desire to run more workloads in the cloud where appropriate.  So we are looking for a solution that is capable of hybrid cloud, or at the very least not to suffer from cloud or vendor lock in.

One thing that does not lack in the IaC space is tool options, and this may be the toughest part to getting started.  As an Infrastructure Engineer, I have spent years looking at different tools for provisioning, configuration management, and deployment. Furthermore, as I have planned out this implementation, I have spent months studying different tools to narrow down the tool chain that I believe is best for us and will work well to compliment each tool's strengths and weaknesses.  There are literally dozens of great tools out there, and there is no one right answer to tool selection.  It all depends on you and your team's preferences, and what works for your organization.  The initial set of tools I will be implementing are:

* [Packer](https://www.packer.io) for image building
* [Terraform](https://www.terraform.io) for provisioning
* [Ansible](https://www.ansible.com) for configuration management
* [Kubernetes](https://kubernetes.io) for container orchestration
* [Rancher](https://rancher.com) for configuring Kubernetes clusters
* [Jenkins](https://jenkins.io) for pipelines

This list is by no means exhaustive, and I already have other ideas for tools that will be needed down the line.  For instance, Chef's [InSpec](https://www.inspec.io/) for infrastructure testing once we have our pipelines running.  

I'm sure someone out there is thinking, "Wow, you are an organization just starting out in DevOps, and jumping right into Kubernetes?" The answer is -- kind of and its complicated. There is a learning curve for not only IaC in general, but also the tools involved in running these environments.  Our plan is to start running some of our team's tools within containers and kubernetes to learn the intricacies and nuances of these enviroments to better support our development teams going forward.  

Just to set some expectations for what I am building.  As stated, our organization as a whole is just beginning to explore the world of DevOps.  We have some pockets on the application side that are doing some really great things, but there is still a lot of transformation that will need to take place.  My team is responsible for hardware, storage, network, and operating systems.  We do help with some application deployment, but it is not entirely our responsiblity.  So to start out we are not looking for entirely imutable infrastructure that we tear down and rebuild with every release.  We may get there, but that is not a goal of this first phase rollout.  The initial goal is to automate as much of the builds as possible, and then be able to control the configuration through code.

## Git

You can't have Infrastructure as Code, if you don't have code, and having code without source control doesn't help anyone.  The first step is to setup a git repository and determine the file structure we want to use.  Again, there is no right answer here, its just what works for your organization.  The stucture I'm starting with is:

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

This structure would have a separate repository for each project.  Each project would have a branch for each lifecycle environment, i.e. Development branch, Testing branch, Staging branch, and the Master branch would be the Production environment.  Branches should only be able to accept Pull Requests from the preceding branch, and each branch would have its own Jenkins Pipeline which would trigger on commits.

The `roles` and `modules` directories would contain git submodules to version controlled Ansible roles and Terraform modules to promote code reuse.  The `environment` directory would contain the variable files for each lifecycle environment.  I plan to name the files/folder the same as the git branch for the environment.  This way we can easily use variables in the pipeline for variable substitution.  The `files` directory is for any files, templates, etc that may be needed, and `outputs` is the landing spot for any files generated by the build.  For example, I plan to generate the ansible inventory file from the Terraform server builds using a `local_file` resource that would be specific to each project.  The `tests` directory would hold any infrastructure tests that we want to run in the build pipeline.  The rest of the files in the directory will be the primary Terraform configuration files which should refer to the terraform modules, the ansible playbook which should call the ansible roles.

This setup gives us the most flexability between custom code and reusable code.  Early on writing a reusable Ansible role could be difficult for some of the administrators that have never done any ansible code previously.  This will allow them to either place ansible commands directly in the playbook or create a custom role under the `roles` directory.  The important part early on in this process is to get people used to performing tasks via code, and not logging in and making changes directly.  In addition, using long living git branches per environment will get people to learn the idea of pull requests and give us the opportunity for peer review of changes.  However, we do need to be cognizant of slowing down the change process too much, and causing frustration to our end users.

## Terraform vs Ansible

Both Ansible and Terraform have a lot of crossover in functionality, but each definitely has its strengths.  Terraform is great at provisioning infrastructure and keeping track of the state that is desired, but is not good at making configuration changes that it cannot very the state of later, for instance, application configurations installed in a VM.  Ansible on the other hand is an excellent tool for configuring individual hosts, and can execute multiple times and expect the same result.  However, its lack of state can be problmatic in some cases.  For example, take the 2 following code snippets for deploying EC2 instances in AWS:

Ansible:

    - ec2:
        count: 5
        image: my-image
        instance_type: t2.micro

Terraform:

    resource "aws_instance" "machines" {
        count         = 5
        ami           = "my-image"
        instance_type = "t2.micro"
    }

On the initial run, both of these would produce the same result, 5 instances of the `my-image` ami.  However, if you wanted to increase the number of machines to 10 by increasing the count variable.  The Terraform code would know about the original 5 images from its state file, but the Anisble code would create 10 new images leaving you with a total of 15.  I know there may be some ways around this, but I'm trying to keep pieces of this process as straight forward as possible and not put too many *hacks* in place.

The intention of this process is to utilize Terraform for infrastructure provisoning, i.e. creating virtual machines, load balancers, networking, etc, and to use Ansible for configuration management of the provisioned infrastructure.  This integration between these tools also leads to some challenges since there is not a defined integration between the 2 tools.  Terraform does have `provisioners` for [Salt](https://www.saltstack.com/), [Chef](https://www.chef.io/), and [Puppet](https://puppet.com/), but nothing for Ansible.  However, Ansible has the advantage of being agentless compared to the other three.  One workaround for this lack of integration is to define a `null_resource` that uses a `local-exec` provisoner to call Ansible.

    resource "null_resource" "ansible" {
        provisioner "remote-exec" {
            inline = ["echo Hello World!"]

            connection {
                type        = "ssh"
                user        = "ansible"
                private_key = "${file(var.ssh_key_private)}"
            }
        }

        provisoner "local-exec" {
            command = "ansible-playbook -u ansible --private-key ${var.ssh_key_private} -i output/hosts playbook.yml"
        }
    }

So, remember what I said about hacks above?  Yeah, me neither...

This code first uses an ssh `remote-exec` to make sure that it is possible to ssh to each host, then calls the ansible playbook from the local agent.  I have found one big downside to this approach, since Terraform is stateful it will not rerun the playbook when there is a change to the playbook itself. This is a problem if we want to continue to manage the hosts in this project via the pipeline.  We would either have to manually taint the `null_resource` everytime we wanted it to be rerun, or taint it programatically to guarantee it gets rerun everytime.  Neither of which is ideal.

Although, since we are planning to run all of this in a Jenkin's pipline, there is another option I prefer.  We can call the ansible playbook in a separate step on the pipeline.  This give us a couple benefits, being able to make just configuration changes to the ansible playbook and not having to rerun the Terraform resource each time.  

In most cases this will work just fine but there are exceptions.  For instance, if I'm setting up a Kubernetes cluster via Terraform, I need to run an Ansible role to configure docker on each host after creating the machine but before configuring Kubernetes.  In these cases, I will run the ansible playbook from within the Terraform configuration, and then run it again in the Ansible stage.  Being that Ansible does a really good job of being idempotent between configuration runs on the hosts, it doesn't hurt anything to get both this initial run and subsequent ones and gives us the benefit of easily changing configuration later.

All that being said, the Internet tells me that the proper way to do everything I stated above is to pre-bake my VM images using Packer, and then slaughter them like cattle everytime I want to make a change to them.  Here is why I'm not going to do that... yet.

This is going to be a big change for our organization, and just switching to a git workflow is going to have a learning curve.  I feel that if we start this process by telling people they cannot login to servers anymore and make changes, they will reject this process from the start.  The better approach for us is to show them the benefits of these processes, and make the repeatable processes easier for them in the long run. Then work up to the idea of making code changes for simple/small/one-off configuration changes.

## The Pipeline

To this point I have eluded to what I want to accomplish, but mentioned little on *how* I want to execute it.  This initial project is to take care of simple server builds in our on-prem virtual environments.  The process flow will have administrators commit code to git.  The commit will trigger a Jenkin's pipeline via a webhook.  Jenkins itself will be running within a kubernetes cluster utilizing the kubernetes plugin.  The pipeline will spin up a slave Pod within kubernetes to execute the pipeline steps.  The pod will contain a separate container for each build tool, i.e. a Terraform container, a Ansible container, and a InSpec container.  These containers will execute their steps against our virtual environments, then terminate.

![CI/CD Pipeline](/img/CI_CD_Pipeline.svg)

The benefits of this workflow is that it is simple and straight forward enough to follow. The Hypervisor is generic and can be a cloud environment, VMware, oVirt, or Xen, as long as there is a Terraform provider to work with it.  Running Jenkins within Kubernetes makes it flexible enough to run anywhere, and we don't need to have build servers sitting around waiting for builds.  This initial workflow also lends itself well to being able to addon application configurations to the end of the pipeline, or utilize separate repositories for the application configuration and access Terraform's remote state to get server details.

 In the follow up posts, I will go through how I setup all the infrastructure and workflows to make this pipeline work.
