+++ 
draft = false
date = 2020-08-23T09:52:21-04:00
title = "Using Packer to Build VM Templates for Oracle VM 3"
description = "Packer lacks a builder for Oracle VM. This is an alternate way to build templates for OVM."
slug = "" 
tags = ["packer", "IaC", "oraclevm", "ovm", "oracle"]
categories = []
externalLink = ""
+++

Anyone that has had the pleasure of running Oracle VM 3(OVM3) has most likely struggled with of the lack of integrations with 3rd party tools and features compared to other hypervisors. For example, there are no live snapshot capabilities and there is no agentless backup solution. It seems that Oracle has not put much development into Oracle VM over the years, and with the release of Oracle VM 4, which is a fork of the upstream oVirt project, OVM3 is most likely near its End-of-Life.  However, OVM3 has a decent VM templating system which is easily extensible, but automating the creation of those templates is challenging. Tools for creating VM images, such as [Hashicorp's Packer](https://www.packer.io/), do not have integrations with OVM3, and for a product nearing End-of-Life, it is not worth the effort to write a custom plugin for it.

Working with a great team from [Boxboat](https://boxboat.com/), we have begun to create VM images for our VMware and Azure environments using Packer, and I wanted to build our OVM templates in the same manner.  While a builder for OVM does not exist within Packer.  There is a builder for VirtualBox that can create an OVF image that should be able to be imported into OVM Manager, but our build server is a virtual machine and I was unable to get VirtualBox working on it.  We are controlling our VM image builds through a CI pipeline, so it is required that we can run this on a server and not a user's computer.  On the build server, we are currently using VMware Workstation to build images for VMware, this builder combined with the `ovftool` can generate a OVA image that can be imported into OVM Manger.  

## Packer

The builder section of my Packer configuration uses the `vmware-iso` builder.  This is building an Oracle Linux 7 image, but would work for any Red Hat Family ISO build.  The ISO build is installed via a kickstart file, which builds a Minimal OS installation.

```
"builders": [
    {
      "type": "vmware-iso",
      "name": "oracle77-ovmiso",
      "headless": "{{user `headless`}}",
      "iso_checksum": "{{user `iso_checksum`}}",
      "iso_urls": [
          "{{user `iso_url`}}"
      ],

      "cpus": 2,
      "memory": 2048,
      "guest_os_type": "oraclelinux-64",
      "tools_upload_flavor": "linux",
      "vm_name": "{{user `image_name`}}",
      "disk_adapter_type": "lsisas1068",
      "disk_size": "{{user `disk_size`}}",
      "disk_type_id": "{{user `disk_type_id`}}",
      "vmx_remove_ethernet_interfaces": true,

      "floppy_files": [ "{{template_dir}}/http/7/ks.cfg" ],
      "boot_command": "<up><wait><tab> text ks=hd:fd0:/ks.cfg net.ifnames=0 biosdevname=0 <enter><wait>",
      "boot_wait": "10s",
      "shutdown_command": "echo 'packer'|sudo -S /sbin/halt -h -p",

      "communicator": "ssh",
      "ssh_username": "packer",
      "ssh_password": "packer",
      "ssh_timeout": "30m",
      "vnc_disable_password": true,
      "output_directory": "{{ user `output_dir` }}"
    }
  ],
```

Now we have a OS installed in our virtual machine, but there are couple steps necessary to make the image a bootable template within OVM.  These are completed in a shell provisioner.

```
"provisioners": [
    {
      "type": "shell",
      "execute_command": "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'",
      "inline": [
        "/usr/bin/ol_yum_configure.sh",
        "yum-config-manager --enable ol7_addons",
        "yum install -y ovmd ovm-template-config* xenstoreprovider libovmapi",
        "dracut --add-drivers \"xen-blkfront xen-netfront\" --force",
        "grub2-mkconfig -o /etc/grub2.cfg",
        "systemctl enable ovm-template-initial-config.service",
        "systemctl enable ovmd.service",
        "sed -i 's/^INITIAL_CONFIG=.*/INITIAL_CONFIG=yes/g' /etc/sysconfig/ovm-template-initial-config"
      ],
      "inline_shebang": "/bin/bash -x",
      "expect_disconnect": true,
      "only": [ "oracle77-ovmiso" ]
    }
  ],

```

The first command in the script will configure the YUM repositories for OEL7.  This is most likely already complete in the image, but is a good failsafe step before moving on.  Next, we enable the Addons repository.  This repository contains the necessary packages for building an OVM template, which are installed in the next step.  

Packages: 
+ ovmd
+ libovmapi
+ xenstoreprovider
+ ovm-template-config*

We want to be able to import this image to OVM, but we are currently running/building on VMware. 

*Note: this same issue exists if building on VirtualBox, described [here](https://docs.oracle.com/cd/E64076_01/E64077/html/vmrns-bugs-3.4.1-virtualbox-export-ol7-does-not-start.html)*  

We need to add the xen block and network drivers to the kernel, then rebuild our initramfs.  Without these steps, when booting the image in OVM, the initramfs will not have the proper drivers in it to find the root partition/logical volume and will not boot.  Next, we enable the OVM Daemon service and the template service, but we don't start them since we aren't running on OVM.  Finally, we flip the `INITIAL_CONFIG` flag to `yes`, so the first boot will run the next time we boot up.

The final step is to setup a `post-processor` to use the `ovftool` to create an OVA file of the virtual machine image.  The OVA file can then be uploaded to a web server and served out over http.  This will allow the OVA to be imported into OVM Manager as a virtual appliance.  When a virtual machine is created from the appliance, it will boot into the template configuration or the required values can be passed to it via messages using the `ovmd` process.

```
"post-processors": [
    {
      "type": "shell-local",
      "inline": [
        "ovftool {{ user `output_dir` }}/{{ user `image_name` }}.vmx {{ user `output_dir` }}/{{ user `image_name` }}.ova"
      ],
      "only": [ "oracle77-ovmiso" ]
    }
  ]

```