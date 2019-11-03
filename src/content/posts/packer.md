+++ 
draft = true
date = 2019-11-02T10:24:24-04:00
title = ""
description = ""
slug = "" 
tags = []
categories = []
externalLink = ""
+++

## Packer

So, what is packer? From the [packer.io](https://www.packer.io/intro/index.html) website:

> Packer is an open source tool for creating identical machine images for multiple platforms from a single source configuration. Packer is lightweight, runs on every major operating system, and is highly performant, creating machine images for multiple platforms in parallel. Packer does not replace configuration management like Chef or Puppet. In fact, when building images, Packer is able to use tools like Chef or Puppet to install software onto the image.

We have been building VMs from image templates for quite a while now, but as a team we were never good at documenting, or updating the documentation, for those template creations.  It was something we did very infrequently, and quite honestly isn't that hard.  I believe that is one of the stumbling blocks to getting started with IaC in an infrastructure organization, none of these tasks are hard for system administrators, but the sum of these tasks take time. So if we can automate the whole process end to end, we can speed up the whole process for the developers or application teams.  So image creation is that first building block that needs to be tackled.

My goal with Packer isn't to pre-bake a complete system, at this time, but to create the base operating system images that will be provisioned by Terraform and configured by Ansible.  As an organization, we aren't quite ready to have fully baked images that just get replaced on deployment in our primary environments, but some of the intention here is to give access to the developers and application teams to contribute configuration code to the servers.  In order to do that, we do need to provide them a place to test those configurations, and have consistent initial build images for them to start from.

Initially, I am not going to put the image creation in the project pipeline.  Eventually, I plan to run the packer builds through their own pipeline and upload the images to an object store, but for this first part I need to execute it locally on my machine since I'm coming at this from scratch.  I'm not going to go through how to install packer, but you can find the instructions [here](https://www.packer.io/intro/getting-started/install.html)

To start building images with packer, we first need to create a template.  I'm going to build a centos 7 image, so I create a directory called  `os-images` and create a `centos7` directory and a json file called `centos-7-server-x86_64.json` with the following content.

```json
    {
      "variables": {
         "ssh_username": "",
         "ssh_password": "",
         "iso_url": "",
         "iso_checksum": "",
         "iso_checksum_type": ""
      },
      "builders": [{
         "type": "qemu",
         "headless": "true",
         "iso_url": "{{user `iso_url`}}",
         "iso_checksum": "{{user `iso_checksum`}}",
         "iso_checksum_type": "{{user `iso_checksum_type`}}",
         "output_directory": "output_centos7",
         "shutdown_command": "echo 'packer' | sudo -S shutdown -P now",
         "disk_size": 10000,
         "format": "qcow2",
         "accelerator": "kvm",
         "http_directory": "http",
         "ssh_username": "{{user `ssh_username`}}",
         "ssh_password": "{{user `ssh_password`}}",
         "ssh_timeout": "20m",
         "vm_name": "centos7",
         "net_device": "virtio-net",
         "disk_interface": "virtio",
        "boot_wait": "10s",
         "boot_command": [
            "<tab> text ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/centos7-ks.cfg<enter><wait>"
         ]
      }]
    }
```

The above template has two sections, `variables` and `builders`.  The variables section defines the values that we will want to change from the command line.  The builders section contains the builder definitions.  In this example, I'm just building a QEMU image to run on Xen, but will be adding builders for VMware, Azure, AWS, and Vagrant in the future.  That way we will have one process for creating identical images on all platforms that we run VMs on.

Next, we need to create the kickstart file that will be used to build the image.  This file will be in a `http` directory specified by the `http_directory` parameter in the json file.  The files in this directory will be served to the installer via http server created by packer. 
The `ks.cfg` file will contain:

```sh
install
url --url ${installation_url}
%{ for repo in repos ~}
repo --name ${repo_name} --baseurl=${repo_url}
%{ endfor ~}

# System authorization information
auth --enableshadow --passalgo=sha512

text

ignoredisk --only-use=vda
# Keyboard layouts
keyboard --vckeymap=us --xlayouts='us'
# System language
lang en_US.UTF-8

# Root password
rootpw ${rootpw}
# System services
services --enabled="chronyd"
# System timezone
timezone America/New_York --isUtc
# System bootloader configuration
bootloader --append=" crashkernel=auto" --location=mbr --boot-drive=vda
autopart --type=lvm
# Partition clearing information
clearpart --none --initlabel

reboot

%packages
@^minimal
@core
chrony
kexec-tools

%end

%addon com_redhat_kdump --enable --reserve-mb='auto'

%end

%anaconda
pwpolicy root --minlen=6 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=6 --minquality=1 --notstrict --nochanges --notempty
%end
```

Now that we have our template, we will create the a `local_file` resource in the `main.tf`

```sh
##### packer-image/main.tf #####

# kickstart file 
resource "local_file" "kickstart" {
    content = templatefile(ks.tmpl, { rootpw})
}
