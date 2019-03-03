+++
title = "Using OpenSCAP for Security Patch Validation"
date = "2018-08-20T00:00:00Z"
draft = false
tags = ["openscap"]
+++

I have been looking for a way to validate patches in my environment.  This validation need to occur outside of the patch repository, because what if the repository is incomplete.  This may seem like overkill (and it probably is), but the validation was really more about creating verifiable evidence that patching had occurred and everything was applied.

My environment consists completely of Red Hat and Red Hat derivative distributions, so most of this will apply to those, but some may be applicable to other distributions as well.

## OpenSCAP
I have previously worked with [OpenSCAP](https://www.open-scap.org/) as a security compliance validation tool.  I had set it up within our Red Hat Satellite infrastructure, and it worked OK.  The issue I had run into previously was that, within Satellite, it did not have a way to customize the security content. None of the SCAP content was 100% compliant with our server configuration, and I did not want to explain how a "failure" on a compliance check should be ignored. So I shelved the project for awhile. I believe content customization has been added in Satellite 6.3, but we aren't there yet and I haven't had time to work with it.

However, it is also possible to perform server scans using just OVAL content, which Red Hat releases with each security errata, and the base scanner tool.  Red Hat updates this content constantly, and provide it for download on their [Security Data page](https://www.redhat.com/security/data/metrics/). 

The great part about this is that we can download this OVAL content at the same time that we synchronize our repositories.  Then, as part of the patching process we can run a scan before and after patching. The final report will "hopefully" show a 100% compliant system.  These scan reports provide us with the verifiable evidence of the security vulnerabilities that we just patched.

OpenSCAP does provide the [SCAP Workbench](https://www.open-scap.org/tools/scap-workbench/) as a tool to run these scans remotely.  I had played with it previously as a way to try and customize SCAP content.  Although, the last time I looked at it, it only ran on a Linux Desktop environment. Unfortunately, I don't have a good place to run a desktop in my environment, and don't really need one more machine to manage. However, OpenSCAP does provide a utilities called oscap-ssh which will allow you to run the scans remotely, and it provides a mechanism to use sudo for these scans.  The results are then created on the server you ran it from.  This makes the evidence collection I'm looking for much simpler.

Probably the one piece we are looking for is the ability to aggregate these scan results into a single report.  The reports that are created individually are great, but I really don't want to open 100+ of them to make sure everything is good.  The scan results are just XML files, so I'm sure something can be written to do this (if it hasn't already).

## How To

The application documentation can be found [here](https://www.open-scap.org/resources/documentation/), and there is also a lot of information in the Red Hat Documentation.

Installation is simple, as it is in the base repositories, and I see on the [downloads](https://www.open-scap.org/download/) page that they do have Debian and Ubuntu packages.

To install the base scanner
```bash
yum install -y openscap-scanner
```

To install the oscap-ssh utility
```bash
yum install -y openscap-utils
```

Next, we need to download the most recent OVAL content from Red Hat
```bash
wget https://www.redhat.com/security/data/oval/com.redhat.rhsa-all.xml.bz2
```

Now we can run the scan using the downloaded content.
```bash
oscap oval eval --results scan-oval-results.xml ./com.redhat.rhsa-all.xml.bz2
```

To run a report on a remote host, you will be prompted for a login password and a password for sudo on the remote host.
```bash
oscap-ssh --sudo demo@192.168.122.71 22 oval eval --results remote-oval-scan-results.xm ./com.redhat.rhsa-all.xml.bz2
```

Finally, a HTML report can be generated from the results.
```bash
oscap oval generate report ./scan-oval-results.xml > ssg-oval-scan-report.html
```



![ssg-report](/img/ssg-report.png)





