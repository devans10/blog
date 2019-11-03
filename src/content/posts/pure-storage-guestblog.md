+++ 
draft = false
date = 2019-06-03T20:55:47-04:00
title = "Pure Storage Guest Blog"
description = "Terraform, welcome to the Pure biosphere!"
slug = "" 
tags = ["terraform","purestorage","golang"]
categories = []
externalLink = ""
+++
*This blog was originally posted on the [Pure Storage Blog](https://blog.purestorage.com/pure-storage-terraform-provider/)*

*For the last couple months, I have been working on some side projects to work with Pure Storage. These projects gave me the opportunity to learn golang and learn more about code development, testing, and even some continuous integration.  The links to these projects are on my [github](https://github.com/devans10), and on the Projects page of this site.*

I began to take a look at [Terraform](https://terraform.io) to use within our environment for infrastructure deployments.  The goal was twofold. First, to have a way to perform scripted, templated deployments using an Infrastructure-as-Code philosophy. Second, to use the same tool across multiple platforms both on-premises (VMware, OracleVM, and [FlashStack](https://www.purestorage.com/flashstack)) and in the cloud (AWS and Azure).  

### What is Terraform?
From the [terraform.io](https://terraform.io/intro/index.html) web site:

> Terraform is a tool for building, changing, and versioning infrastructure safely and efficiently. Terraform can manage existing and popular service providers as well as custom in-house solutions.

> Configuration files describe to Terraform the components needed to run a single application or your entire datacenter. Terraform generates an execution plan describing what it will do to reach the desired state, and then executes it to build the described infrastructure. As the configuration changes, Terraform is able to determine what changed and create incremental execution plans which can be applied.

> The infrastructure Terraform can manage includes low-level components such as compute instances, storage, and networking, as well as high-level components such as DNS entries, SaaS features, etc.

Terraform looked like a good choice, as there were already provider plugins for most of our stacks, both official and community supported. There was one that did not yet exist, a provider for our Pure Storage [FlashArray](https://www.purestorage.com/flash)™.  So, I decided to take on the project of creating the Terraform Provider Flash. The biggest challenge of this project is that all of Terraform and its providers are written in Go, a programming language that I was not familiar with and would have to learn along the way.  

Terraform itself abstracts the APIs for many different infrastructure services. I was very familiar with the [Pure Storage Python REST client](https://pypi.org/project/purestorage) and it is possible to interface with different languages from within the Terraform Provider framework.  However, that makes things much more difficult and harder to support. Thus, the first step in this project was to create a Go wrapper library for the Pure FlashArray API.

I created [Pugo](https://github.com/devans10/pugo), a GO REST client, as a separate project since it can be useful to more than just the Terraform Provider. As of the date of writing, the Go client validation occurred at version 1.15 of the Pure FlashArray API.  It is not yet full-featured but does support all the REST endpoints for Volumes, Hosts, Host Groups, and Protection Groups. While this is not the focus of this blog post,note that Pugo also includes an implementation of the Pure1 REST API (as noted in a previous [Pure1 REST API blog post](https://blog.purestorage.com/pure1-rest-api-part-1/)).

Once I had completed the Go REST Client, I was able to proceed with the [Terraform Provider Flash](https://github.com/devans10/terraform-provider-flash). ~~Watch the video below to see it in action as I demo it:~~

If you’re interested in playing with the source code I put together for that demo video, check out the [puredemo GitHub repo](https://github.com/devans10/puredemo).

Now, let’s do a quick walk-through on how to use the provider in the section below.

### Terraform Provider Usage
First, you will need to install Terraform. The latest binary can be downloaded here. Once the binary file is in your path, you can verify the install by running `terraform` which should generate output similar to this:

```sh
$ terraform
Usage: terraform [--version] [--help] <command> [args]

The available commands for execution are listed below.
The most common, useful commands are shown first, followed by
less common or more advanced commands. If you're just getting
started with Terraform, stick with the common commands. For the
other commands, please read the help and docs before usage.

Common commands:
    apply              Builds or changes infrastructure
    console            Interactive console for Terraform interpolations
# ...
```

Next, download the latest Terraform Provider Flash release for your platform here.

Alternatively, you could also build the Provider Plugin from the source code. To do this, you will need a working Go install. You can then run the following script to clone the provider GitHub repository and build it:

```sh
$ mkdir -p $GOPATH/src/github.com/devans10; cd $GOPATH/src/github.com/devans10
$ git clone git@github.com:devans10/terraform-provider-flash
$ cd $GOPATH/src/github.com/devans10/terraform-provider-flash
$ make build
```

Copy the binary file to the user plugin directory, located at %APPDATA%\terraform.d\plugins on Windows and ~/.terraform.d/plugins on other systems.

Create a file in the user’s home directory called .terraformrc and add the following text:

```sh
providers {
    purestorage = "$HOME/terraform.d/plugins/terraform-provider-flash"
}
```

Now, create a directory to store your Terraform configuration files. All Terraform configuration files use the extension \*.tf.

Next, create a file for your configuration, pure_example.tf, inside the directory you just created and enter the following piece of code:

```sh
provider "purestorage" {
  target = "flasharray.example.com"
  api_token = "abcdefgh-ijkl-mnop-qrst-123456789012"
}

resource "random_id" "tf_volume_id" {
  byte_length = 1
}

resource "purestorage_volume" "testvol_tf_res" {
  name = "testvol-tf-${random_id.tf_volume_id.dec}"
  size = "1048000000"
}
```

The first section configures the provider. The `target` is either the FQDN of your array or its IP address. The `api_token` value must contain a valid API token that you generate from your FlashArray Management website in the Settings->Users section. The provider has a couple of options for authentication, documented in the project’s documentation.  API tokens, user credentials, and even array addresses themselves should be obfuscated either with .tfvars files or through the use of a credential store, such as HashiCorp Vault. Furthermore, care should be taken to verify they are not checked into a public code repository. 

The second section specifies the resource we would like to create, a volume of a specific size.  It is also possible to clone an existing volume by specifying the source parameter, as well as creating other resources, such as hosts and protection groups.

Now that we have our base configuration, we need to initialize the configuration with `terraform init`

```sh
$ terraform init

Initializing provider plugins...

Terraform has been successfully initialized!
```

With the configuration initialized, try running `terraform plan` to see the changes required.

```sh
$ terraform plan
Refreshing Terraform state in-memory prior to plan...
The refreshed state will be used to calculate this plan, but will not be
persisted to local or remote state storage.


------------------------------------------------------------------------

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + purestorage_volume.testvol_tf_res
      id:      <computed>
      created: <computed>
      name:    "testvol-tf"
      serial:  <computed>
      size:    "1048000000"
      source:  <computed>


Plan: 1 to add, 0 to change, 0 to destroy.

------------------------------------------------------------------------

Note: You didn't specify an "-out" parameter to save this plan, so Terraform
can't guarantee that exactly these actions will be performed if
"terraform apply" is subsequently run.
```

Here, we see that an execution plan has been created.  It will generate the volume specified in the configuration.  Next, run `terraform apply` to run the plan and apply it to your Pure FlashArray.

```sh
$ terraform apply

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + purestorage_volume.testvol_tf_res
      id:      <computed>
      created: <computed>
      name:    "testvol-tf"
      serial:  <computed>
      size:    "1048000000"
      source:  <computed>


Plan: 1 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: 


At this point, Terraform prompts you to confirm that you want to apply the plan. Type yes to confirm. Terraform proceeds by creating the volume.

purestorage_volume.testvol_tf_res: Creating...
  created: "" => "<computed>"
  name:    "" => "testvol-tf"
  serial:  "" => "<computed>"
  size:    "" => "1048000000"
  source:  "" => "<computed>"
purestorage_volume.testvol_tf: Creation complete after 1s (ID: testvol_tf)

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

With the `apply` Terraform operation, we see the plan, are prompted  for confirmation, and then the plan is executed.  We can see the results with `terraform show`

```sh
$ terraform show
purestorage_volume.testvol_tf:
  id = testvol_tf
  created = 2019-01-03T01:14:57Z
  name = testvol_tf
  serial = 5988DAFC6983439F0014EE6E
  size = 1048000000
  source = 
```

Now let's add some items to our infrastructure...

```sh
provider "purestorage" {
  target = "flasharray.example.com"
  api_token = "12345-678910-abcdefg-hijklm"
}

resource "purestorage_volume" "testvol_tf_res" {
  name = "testvol-tf"
  size = "1048000000"
}

resource "purestorage_volume" "testvol2_tf_res" {
  name = "testvol2-tf"
  source = "${purestorage_volume.testvol_tf_res.name}"
}

resource "purestorage_host" "testhost_tf_res" {
  name = "testhost-tf"
  wwn = ["0000999900009999"]
}

resource "purestorage_hostgroup" "testhgroup_tf_res" {
  name = "testhgroup-tf"
  hosts = ["${purestorage_host.testhost_tf_res.name}"]
  volume {
    vol = "${purestorage_volume.testvol_tf_res.name}"
    lun = 253
  }
  volume {
    vol = "${purestorage_volume.testvol2_tf_res.name}"
    lun = 252
  }
}

resource "purestorage_protectiongroup" "testpgroup_res" {
  name = "testpgroup"
  hgroups = ["${purestorage_hostgroup.testhgroup_tf_res.name}"]
}
```

At this point, our Terraform plan is a bit more complex.  We have added a second volume, as a copy of the first volume, thanks to the “source" parameter. Notice that the source volume name is referenced by a variable using dot notation from the original resource.  Next, we add a host with a WWN, a hostgroup, and a protection group.  By using the variable, Terraform recognizes this as an implicit dependency.

Run `terraform apply` to see what will change before confirming it…

```sh
$ terraform apply
purestorage_volume.testvol_tf_res: Refreshing state... (ID: testvol_tf)

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + purestorage_host.testhost_tf_res
      id:                    <computed>
      host_password:         <computed>
      name:                  "testhost-tf"
      target_password:       <computed>

  + purestorage_hostgroup.testhgroup_tf_res
      id:                    <computed>
      hosts.#:               "1"
      hosts.0:               "testhost-tf"
      name:                  "testhgroup-tf"
      volume.#:              "2"
      volume.1319609530.lun: "252"
      volume.1319609530.vol: "testvol2-tf"
      volume.3146878713.lun: "253"
      volume.3146878713.vol: "testvol-tf"

  + purestorage_protectiongroup.testpgroup
      id:                    <computed>
      all_for:               "86400"
      days:                  "7"
      hgroups.#:             "1"
      hgroups.0:             "testhgroup-tf"
      name:                  "testpgroup"
      per_day:               "4"
      replicate_enabled:     "false"
      replicate_frequency:   "14400"
      snap_enabled:          "false"
      snap_frequency:        "3600"
      source:                <computed>
      target_all_for:        "86400"
      target_days:           "7"
      target_per_day:        "4"

  + purestorage_volume.testvol2_tf
      id:                    <computed>
      created:               <computed>
      name:                  "testvol2-tf"
      serial:                <computed>
      size:                  <computed>
      source:                "testvol-tf"


Plan: 4 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

purestorage_host.testhost_tf_res: Creating...
  host_password:   "" => "<computed>"
  name:            "" => "testhost-tf"
  target_password: "" => "<computed>"
purestorage_volume.testvol2_tf_res: Creating...
  created: "" => "<computed>"
  name:    "" => "testvol2-tf"
  serial:  "" => "<computed>"
  size:    "" => "<computed>"
  source:  "" => "testvol-tf"
purestorage_host.testhost_tf_res: Creation complete after 1s (ID: testhost-tf)
purestorage_volume.testvol2_tf_res: Creation complete after 1s (ID: testvol2-tf)
purestorage_hostgroup.testhgroup_tf_res: Creating...
  hosts.#:               "0" => "1"
  hosts.0:               "" => "testhost-tf"
  name:                  "" => "testhgroup-tf"
  volume.#:              "0" => "2"
  volume.1319609530.lun: "" => "252"
  volume.1319609530.vol: "" => "testvol2-tf"
  volume.3146878713.lun: "" => "253"
  volume.3146878713.vol: "" => "testvol-tf"
purestorage_hostgroup.testhgroup_tf_res: Creation complete after 1s (ID: testhgrouptf)
purestorage_protectiongroup.testpgroup: Creating...
  all_for:             "" => "86400"
  days:                "" => "7"
  hgroups.#:           "0" => "1"
  hgroups.0:           "" => "testhgroup-tf"
  name:                "" => "testpgroup"
  per_day:             "" => "4"
  replicate_enabled:   "" => "false"
  replicate_frequency: "" => "14400"
  snap_enabled:        "" => "false"
  snap_frequency:      "" => "3600"
  source:              "" => "<computed>"
  target_all_for:      "" => "86400"
  target_days:         "" => "7"
  target_per_day:      "" => "4"
purestorage_protectiongroup.testpgroup_res: Creation complete after 1s (ID: testpgroup)

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

The resources, especially the Protection Group, have some default values.  These values can also be controlled and specified within the Terraform plan.

Finally, let's destroy our infrastructure with `terraform destroy`

```
$ terraform destroy
purestorage_host.testhost_tf_res: Refreshing state... (ID: testhost-tf)
purestorage_volume.testvol_tf: Refreshing state... (ID: testvol_tf)
purestorage_volume.testvol2_tf: Refreshing state... (ID: testvol2_tf)
purestorage_hostgroup.testhgroup_tf: Refreshing state... (ID: testhgrouptf)
purestorage_protectiongroup.testpgroup: Refreshing state... (ID: testpgroup)

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  - destroy

Terraform will perform the following actions:

  - purestorage_host.testhost_tf_res

  - purestorage_hostgroup.testhgroup_tf_res

  - purestorage_protectiongroup.testpgroup_res

  - purestorage_volume.testvol2_tf_res

  - purestorage_volume.testvol_tf_res


Plan: 0 to add, 0 to change, 5 to destroy.

Do you really want to destroy all resources?
  Terraform will destroy all your managed infrastructure, as shown above.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes

purestorage_protectiongroup.testpgroup_res: Destroying... (ID: testpgroup)
purestorage_protectiongroup.testpgroup_res: Destruction complete after 1s
purestorage_hostgroup.testhgroup_tf_res: Destroying... (ID: testhgrouptf)
purestorage_hostgroup.testhgroup_tf_res: Destruction complete after 1s
purestorage_volume.testvol2_tf_res: Destroying... (ID: testvol2_tf)
purestorage_host.testhost_tf_res: Destroying... (ID: testhosttf)
purestorage_host.testhost_tf_res: Destruction complete after 0s
purestorage_volume.testvol2_tf_res: Destruction complete after 0s
purestorage_volume.testvol_tf_res: Destroying... (ID: testvol_tf)
purestorage_volume.testvol_tf_res: Destruction complete after 0s

Destroy complete! Resources: 5 destroyed.
```

All of the infrastructure that you had created through the Terraform configuration above has now been destroyed.  However, there is one caveat; the provider does NOT eradicate volumes or protection groups as a safety measure against accidental data deletion.  Therefore, if you would like to execute `terraform apply` again to recreate it as a fresh copy, you would either need to wait 24 hours or manually eradicate the volumes and protection group.  A good practice to avoid this protection in a production environment would be to use a randomized volume name.  This can be achieved by using the Terraform random_id provider, and appending the generated ID to the volume name.  This gives the ability to recreate an infrastructure immediately, and provides the protection of the 24-hour deletion clock provided by the Pure Storage FlashArray.

### Conclusion
There is a lot that can be done with Terraform using variables, workspaces, modules, and multiple providers.  If you would like to learn more about Terraform, HashiCorp has a good tutorial.

While the Terraform Provider Flash has basic functionality, I do plan to continue maintaining it and adding more features. If you have any interest in contributing to the provider, I am very open to issues or pull requests to the GitHub repository. There is also a project website that has the full documentation for the provider and links to the binary downloads.  If you have questions or would like to interact with me, please consider joining the Pure Storage Code Slack Community, where I’m @DaveEvans, and there are channels for both #golang and #terraform. 

