+++
title = "Terraform Provider for PureStorage FlashArray"
date = "2019-03-03T00:00:00Z"
draft = true
tags = ["terraform", "purestorage", "golang"]
+++

About a month and a half ago, I began to take a look at Terraform to use within our environment for infrastructure deployments.  The goal was twofold. First, have a way to perform scripted, template style deployments using an Infrastructure-as-code philosophy. Second, to be able to use the same tool across multiple platforms both on-prem (VMWare, OracleVM, and FlashStack) and in the cloud (AWS and Azure).  

### What is Terraform?

From the terraform.io web site:

> Terraform is a tool for building, changing, and versioning infrastructure safely and efficiently. Terraform can manage existing and popular service providers as well as custom in-house solutions.
> Configuration files describe to Terraform the components needed to run a single application or your entire datacenter. Terraform generates an execution plan describing what it will do to reach the desired state, and then executes it to build the described infrastructure. As the configuration changes, Terraform is able to determine what changed and create incremental execution plans which can be applied.
> The infrastructure Terraform can manage includes low-level components such as compute instances, storage, and networking, as well as high-level components such as DNS entries, SaaS features, etc.

Terraform looked like a good choice, as there were already provider plugins for most of our stacks, both official and community supported.  The one hole I found was, there was no provider for our PureStorage FlashArray.  So, I decided to take on the project of creating the Terraform Provider for the Purestorage FlashArray.  The biggest challenge of this project, is that all of Terraform, and the providers for it, are written in Go.  A programming language I was not familiar with, and would have to learn along the way.  Terraform itself abstracts the APIs for many different infrastructure services.  I was very familiar with the Pure Python REST client, and it is possible to interface with different languages from within the Terraform Provider framework.  However, that just makes things much more difficult and harder to support.  That made the first step in this project to create a REST client for the Pure FlashArray API written in Go.
I created the G0 REST Client as a separate project, since it can be useful to more than just the Terraform Provider.  The Go client is tested against v1.15 of the Pure FlashArray API.  It is not yet full featured, but does support all functionality for Volumes, Hosts, Hostgroups, and Protection Groups. 
Once the REST Client was written, work was able to proceed on the Terraform Provider for Purestorage.  I will do a quick walk-through on how to use the provider below.

### Terraform Provider Usage
First, you will need to install Terraform.  The latest binary can be downloaded [here.](https://www.terraform.io/downloads.html) Once the binary file in in your path, you can verify the install by running terraform which should generate output similar to this:

```bash
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

Next, download the latest release binary for your platform here.
Or, build the Provider Plugin from source. To do this you will need a working [Go install.](https://golang.org/doc/install)

Copy the binary file to the user plugin directory, located at `%APPDATA%\terraform.d\plugins` on Windows and `~/.terraform.d/plugins` on other systems.
Now create a directory to store your Terraform configuration files. All Terraform configuration files use the extension `*.tf`.
Next, create a file for your configuration, `pure_example.tf`, inside the directory you just created.

```bash
provider "purestorage" {
  target = "flasharry.example.com"
  api_token = "12345-678910-abcdefg-hijklm"
}

resource "purestorage_volume" "testvol_tf" {
  name = "testvol_tf"
  size = "1048000000"
}
```

The first section configures the provider. Optionally, it will accept a username and password instead of an API token.  The second block is the resource that will be created. In this case a volume of the specified size.  It is also possible to clone an existing volume by specifying the `source` parameter.
Now that we have our base configuration, we need to initialize the configuration with `terraform init`

```bash
$ terraform init

Initializing provider plugins...

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```

With the configuration initialized, try running terraform plan to see the changes required.

```bash
$ terraform plan
Refreshing Terraform state in-memory prior to plan...
The refreshed state will be used to calculate this plan, but will not be
persisted to local or remote state storage.


------------------------------------------------------------------------

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + purestorage_volume.testvol_tf
      id:      <computed>
      created: <computed>
      name:    "testvol_tf"
      serial:  <computed>
      size:    "1048000000"
      source:  <computed>


Plan: 1 to add, 0 to change, 0 to destroy.

------------------------------------------------------------------------

Note: You didn't specify an "-out" parameter to save this plan, so Terraform
can't guarantee that exactly these actions will be performed if
"terraform apply" is subsequently run.
```

Here we see that an execution plan has been created, and it will create the volume specified in the configuration.  Next, run `terraform apply`

```bash
$ terraform apply

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + purestorage_volume.testvol_tf
      id:      <computed>
      created: <computed>
      name:    "testvol_tf"
      serial:  <computed>
      size:    "1048000000"
      source:  <computed>


Plan: 1 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

purestorage_volume.testvol_tf: Creating...
  created: "" => "<computed>"
  name:    "" => "testvol_tf"
  serial:  "" => "<computed>"
  size:    "" => "1048000000"
  source:  "" => "<computed>"
purestorage_volume.testvol_tf: Creation complete after 1s (ID: testvol_tf)

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

With apply, you see the plan, are asked for confirmation, then the plan is executed.  We can see the results with `terraform show`

```
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

```bash
provider "purestorage" {
  target = "flasharry.example.com"
  api_token = "12345-678910-abcdefg-hijklm"
}

resource "purestorage_volume" "testvol_tf" {
  name = "testvol_tf"
  size = "1048000000"
}

resource "purestorage_volume" "testvol2_tf" {
  name = "testvol2_tf"
  source = "${purestorage_volume.testvol_tf.name}"
}

resource "purestorage_host" "testhost_tf" {
  name = "testhosttf"
  wwn = ["0000999900009999"]
}

resource "purestorage_hostgroup" "testhgroup_tf" {
  name = "testhgrouptf"
  hosts = ["${purestorage_host.testhost_tf.name}"]
  volume {
    vol = "${purestorage_volume.testvol_tf.name}"
    lun = 253
  }
  volume {
    vol = "${purestorage_volume.testvol2_tf.name}"
    lun = 252
  }
}

resource "purestorage_protectiongroup" "testpgroup" {
  name = "testpgroup"
  hgroups = ["${purestorage_hostgroup.testhgroup_tf.name}"]
}
```

Ok, there is a lot going on here.  We have added a 2nd volume, but this volume will be a copy of the first volume.  Notice that the source volume name is referenced by a variable using dot notation from the original resource.  Next, we add a host with a WWN, a hostgroup, and finally a protection group.  By using the variable, Terraform recognizes this as an implicit dependency.
Run `terraform apply` to see what will change before confirming it...

```bash
$ terraform apply
purestorage_volume.testvol_tf: Refreshing state... (ID: testvol_tf)

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  + purestorage_host.testhost_tf
      id:                    <computed>
      host_password:         <computed>
      name:                  "testhosttf"
      target_password:       <computed>

  + purestorage_hostgroup.testhgroup_tf
      id:                    <computed>
      hosts.#:               "1"
      hosts.0:               "testhosttf"
      name:                  "testhgrouptf"
      volume.#:              "2"
      volume.1319609530.lun: "252"
      volume.1319609530.vol: "testvol2_tf"
      volume.3146878713.lun: "253"
      volume.3146878713.vol: "testvol_tf"

  + purestorage_protectiongroup.testpgroup
      id:                    <computed>
      all_for:               "86400"
      days:                  "7"
      hgroups.#:             "1"
      hgroups.0:             "testhgrouptf"
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
      name:                  "testvol2_tf"
      serial:                <computed>
      size:                  <computed>
      source:                "testvol_tf"


Plan: 4 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

purestorage_host.testhost_tf: Creating...
  host_password:   "" => "<computed>"
  name:            "" => "testhosttf"
  target_password: "" => "<computed>"
purestorage_volume.testvol2_tf: Creating...
  created: "" => "<computed>"
  name:    "" => "testvol2_tf"
  serial:  "" => "<computed>"
  size:    "" => "<computed>"
  source:  "" => "testvol_tf"
purestorage_host.testhost_tf: Creation complete after 1s (ID: testhosttf)
purestorage_volume.testvol2_tf: Creation complete after 1s (ID: testvol2_tf)
purestorage_hostgroup.testhgroup_tf: Creating...
  hosts.#:               "0" => "1"
  hosts.0:               "" => "testhosttf"
  name:                  "" => "testhgrouptf"
  volume.#:              "0" => "2"
  volume.1319609530.lun: "" => "252"
  volume.1319609530.vol: "" => "testvol2_tf"
  volume.3146878713.lun: "" => "253"
  volume.3146878713.vol: "" => "testvol_tf"
purestorage_hostgroup.testhgroup_tf: Creation complete after 1s (ID: testhgrouptf)
purestorage_protectiongroup.testpgroup: Creating...
  all_for:             "" => "86400"
  days:                "" => "7"
  hgroups.#:           "0" => "1"
  hgroups.0:           "" => "testhgrouptf"
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
purestorage_protectiongroup.testpgroup: Creation complete after 1s (ID: testpgroup)

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.
```

The resources, especially the Protection group, have some default values.  These values can also be controlled and specified within the Terraform plan.
Finally, let's destroy our infrastructure with `terraform destroy`

```bash
$ terraform destroy
purestorage_host.testhost_tf: Refreshing state... (ID: testhosttf)
purestorage_volume.testvol_tf: Refreshing state... (ID: testvol_tf)
purestorage_volume.testvol2_tf: Refreshing state... (ID: testvol2_tf)
purestorage_hostgroup.testhgroup_tf: Refreshing state... (ID: testhgrouptf)
purestorage_protectiongroup.testpgroup: Refreshing state... (ID: testpgroup)

An execution plan has been generated and is shown below.
Resource actions are indicated with the following symbols:
  - destroy

Terraform will perform the following actions:

  - purestorage_host.testhost_tf

  - purestorage_hostgroup.testhgroup_tf

  - purestorage_protectiongroup.testpgroup

  - purestorage_volume.testvol2_tf

  - purestorage_volume.testvol_tf


Plan: 0 to add, 0 to change, 5 to destroy.

Do you really want to destroy all resources?
  Terraform will destroy all your managed infrastructure, as shown above.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes

purestorage_protectiongroup.testpgroup: Destroying... (ID: testpgroup)
purestorage_protectiongroup.testpgroup: Destruction complete after 1s
purestorage_hostgroup.testhgroup_tf: Destroying... (ID: testhgrouptf)
purestorage_hostgroup.testhgroup_tf: Destruction complete after 1s
purestorage_volume.testvol2_tf: Destroying... (ID: testvol2_tf)
purestorage_host.testhost_tf: Destroying... (ID: testhosttf)
purestorage_host.testhost_tf: Destruction complete after 0s
purestorage_volume.testvol2_tf: Destruction complete after 0s
purestorage_volume.testvol_tf: Destroying... (ID: testvol_tf)
purestorage_volume.testvol_tf: Destruction complete after 0s

Destroy complete! Resources: 5 destroyed.
```

Now all the infrastructure that you had created has now been destroyed.  However, there is one caveat to this.  The provider does NOT eradicate volumes or protection groups.  So, if you would want to run `terraform apply` again to recreate it a fresh copy, you would either need to wait 24 hours or manually eradicate the volumes and protection group.
There is a lot that can be done with Terraform using variables, workspaces, modules, and multiple providers.  If you would like to learn more about Terraform, Hashicorp has a good tutorial.
