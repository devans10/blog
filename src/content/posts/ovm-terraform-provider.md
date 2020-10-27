+++ 
draft = false
date = 2020-09-22T20:12:03-04:00
title = "OVM Terraform Provider"
description = "A Terraform resource provider for Oracle VM 3"
slug = "" 
tags = ["terraform", "ovm", "IaC"]
categories = []
externalLink = ""
+++

[Oracle VM 3(OVM)](https://www.oracle.com/virtualization/vm-server-for-x86/) is the original vituralization solution from everybody's favorite software company.  I say "original" because last year they completely replaced the solution with a new version.  The new solution, [Oracle Linux Virtualization Manager](https://blogs.oracle.com/virtualization/announcing-oracle-linux-virtualization-manager) is based on the upstream oVirt project and utilizes KVM for its hypervisor.  Oracle VM utilizes the Xen hypervisor, so any migration to the new version will require a rebuild of the virtual environment and a migration of the virtual machines.  As it stands, Oracle is ending Premier support for OVM 3 in March 2021, and putting it on Extended support until March of 2024.  That is a roundabout way of saying, that this product is not long for this world.

Anyone that has had the pleasure of working with this virtualization platform, has definitely experienced the lack of integrations with with 3rd party tools and a deficiency of features compared to more mature offerings, such as VMware.  However, the one thing OVM does have going for it is a decent API and a easily extensible virtual machine templating system.

So, while OVM does not have a long life span, I do want to utilize some infrastructure-as-code practices with the machines that we do have running within that environment.  There was a OVM [Terraform](https://terraform.io) Provider project that had been started by [Bjorn Ahl](https://github.com/dbgeek), but he had posted a notice that he was no longer able to support the provider.  The provider as it stood, did not completely meet my needs.  This led to me forking both his provider and the go-ovm-helper repositories, and beginning to modify them.

The repositories for the forked projects can be found on my Github.

+ [terraform-ovm-provider](https://github.com/devans10/terraform-provider-ovm)
+ [go-ovm-helper](https://github.com/devans10/go-ovm-helper)

There have been some signficant changes for 3rd-party community terraform providers that were introduced in Terraform v0.13.x.  Mainly, removing the ability to define provider binaries in the `.terraformrc` file. The feature was depreciated and removed because it did not provide a way to correctly version control the providers.  While it is not impossible to have a local mirror of a provider with correct versioning, it is definately much harder.  This lead me to publishing the provider on the [Terrafor Registry](https://registry.terraform.io/providers/devans10/ovm/latest).  Publishing the provider and allowing Terraform to to download and install it automatically.

My main use-case for the provider is to spin up VM template images that were created with [Packer](https://packer.io), which I described in my last blog [post.](https://www.daveevans.us/posts/packer-ovm-templates/)

To use the provider with Terraform v0.13.x, you must list it in a `required_providers` block in your terraform config.

```
terraform {
  required_providers {
    ovm = {
      source  = "devans10/ovm"
      version = "1.0.2"
    }
  }
}
```

Configuring the provider can be done in two ways.  Either, listing the username, password, and OVM Manager endpoint in the provider as shown below, or setting the environment variables `OVM_USERNAME`, `OVM_PASSWORD`, and `OVM_ENDPOINT`

```
provider "ovm" {
  user       = var.username
  password   = var.password
  entrypoint = var.entrypoint
}
```

The endpoint is the full URL to the OVM Manager, i.e. https://localhost:7002/.

The majority of the changes I made to the provider were to add Data Sources.  This allowed me to lookup the details about the environment based just on the names of the resources rather than the cryptic IDs.

### ovm_network

```
data "ovm_network" "network" {
    name = "vm-public"
}
```

This data source returns the ID object of the virtual network.  This allows you to set the network of a new virtual NIC on the template.  The VM images created with Packer, do not import with any attached NICs.  The must be added at create time.

### ovm_repository

```
data "ovm_repository" "repo" {
    name = "my-repository"
}
```

This data source returns the ID of the OVM repository where the VMs and virtual disks are stored.

### ovm_serverpool

```
data "ovm_serverpool" "pool" {
    name = "my-serverpool"
}
```

The `ovm_serverpool` data source returns the ID of the server cluster the VM will run on.

### ovm_vm

```
data "ovm_vm" "virtualmachine" {
    name = "my-tmpl-vm"
}
```

This data source returns all the information for a VM.  This is the way to look up a virtual machine template to create the new VM from.  In my workflow, I will lookup the packer image that was imported.

### Resources

Here is an example Terraform configuration to create a VM from a template.

```
data "ovm_repository" "repo" {
  name = var.repository
}

data "ovm_vm" "ovm_template" {
  name         = var.machine_image
  repositoryid = data.ovm_repository.repo
}

data "ovm_serverpool" "serverpool" {
  name = var.server_pool
}

data "ovm_network" "network" {
  name = var.network
}

# //Creating VmCloneCustomizer
resource "ovm_vmcd" "oel7_tmpl_cst" {
  vmid        = data.ovm_vm.ovm_template.id
  name        = "oe7_tmpl_cst"
  description = "Desc oel7 cust"
}

# //Defining Vm Clone Storage Mapping
resource "ovm_vmcsm" "oel7_vmclonestoragemapping" {
  for_each = toset(data.ovm_vm.ovm_template.vmdiskmappingids.*.value)

  vmdiskmappingid     = each.key
  vmclonedefinitionid = ovm_vmcd.oel7_tmpl_cst.id
  repositoryid        = data.ovm_repository.repo
  name                = "oel_cust_storage"
  clonetype           = "SPARSE_COPY"
}

resource "ovm_vm" "cloneoel7" {
  name = "cloneoel7Vm"

  repositoryid = data.ovm_repository.repo
  serverpoolid = data.ovm_serverpool.serverpool

  memorylimit         = 4096
  memory              = 4096
  cpucount            = 4
  cpucountlimit       = 4
  vmdomaintype        = "XEN_HVM_PV_DRIVERS"
  imageid             = data.ovm_vm.ovm_template.id
  ostype              = "Oracle Linux 7"
  vmclonedefinitionid = ovm_vmcd.oel7_tmpl_cst.id

  virtualnic {
    networkid = data.ovm_network.network
  }

  sendmessages = {
    "com.oracle.linux.network.hostname"    = "cloneoel7vm"
    "com.oracle.linux.network.device.0"    = "eth0"
    "com.oracle.linux.network.bootproto.0" = "dhcp"
    "com.oracle.linux.network.onboot.0"    = "yes"
    "com.oracle.linux.root-password"       = "Welcome!"
  }

  depends_on = [ovm_vmcsm.oel7_vmclonestoragemapping]
}
```

There is a lot to unpack there.  The first four blocks look up the data for the `serverpool`, `repository`, `template`, and `network`.  Next, we create a clone customizer for the VM template.  This object allows us to map the virtual disks and virtual nics to new repositories and networks if we desire.  

We have to create new storage mappings for the virtual disks attached to the template.  The images from Packer actually have two disks, a virtual hard disk for the operating system and a CD-ROM drive that was used to mount the ISO image in Packer.  A `for_each` loop on the vm data source's `vmdiskmappingids` allows us to map those to the new repository.

Finally, we create the resource for the VM.  At this time we are able to edit the resources for the VM, i.e. CPU, Memory, etc.  We can add a virtual nic for the network, and we can send messages to the VM to configure the template.  There are a number of settings that can be set to configure the VM.  The ones shown are the minimum to get the VM up and running.  

I do not have plans to add a lot of functionality to this provider, since OVM is getting so close to end of support.  However, this is a minimal configuration required to get done what is needed.  Documentation for the provider can be found on the provider page within the [Terraform Registry.](https://registry.terraform.io/providers/devans10/ovm/latest/docs/resources/vm)