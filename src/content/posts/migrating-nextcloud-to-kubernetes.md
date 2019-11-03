+++ 
draft = true
date = 2019-06-29T21:15:41-04:00
title = "Migrating Nextcloud to Kubernetes"
description = "Process for moving a Nextcloud instance from a VM to Kubernetes"
slug = "" 
tags = ["nextcloud", "kubernetes"]
categories = []
externalLink = ""
+++

A little under a year ago I decided to [migrate from Dropbox to Nextcloud](/posts/moving-from-dropbox-to-nextcloud/) and I couldn't be happier with the results.  It has been a very painless experience.  I have upgraded multiple times without issue. Automatic photo sync from my phone works flawlessly, and I have begun to do much more with it than I ever did with Dropbox.  

I have only had one hiccup with the install, and quite honestly it was my fault.  Every year I put together and end-of-year video together for my wife's Kindergarten class.  This year we wanted to be able to distribute the video to the parents, but we didn't want to publish it on YouTube.  We created cards with a QR code that pointed to the share link from my Nextcloud instance, except I accidently gave them a link to play the video instead of just download it. So later that day when 50+ people started streaming the video from my Nextcloud instance, it got overloaded and crashed.  Essentially what happened was the OOM killer, killed off the database.

This incident got me thinking.  What if I look to run my Nextcloud on my Kubernetes instance.  That way if some part of it goes down, Kubernetes would be able to restart it.  In addition, I may be able to save a bit of money, too.  I just have a couple static web sites running on the cluster, and there should be plenty of compute left to also run Nextcloud.

## The Plan

First things first, I need to find out if running Nextcloud on Kubernetes is possible.  A quick search found that there are [Helm charts available for Nextcloud.](https://github.com/helm/charts/tree/master/stable/nextcloud) The charts include dependancies for separate MySql database and redis pods.  This is a benefit since those could allow those pieces to run on separate compute nodes. In addtion, this chart does include setting up persistent storage for both the Nextcloud data directory and the MySql database.

The Nextcloud documenation has a section on [migrating to a new server.](https://docs.nextcloud.com/server/16/admin_manual/maintenance/migrating.html) This isn't "exactly" what I'm doing, but this process can be adapted.  The basic steps are:

+ Setup the new instance via the Helm chart
+ Put current Nextcloud instance into maintenace mode
+ Backup folders and DB
+ Restore backups on new instance
+ Test new instance
+ Turn off the old and on the new instance

The good thing with this process is the old instance is not affected.  So if anything does go wrong, I can always just turn the original instance back on.

## Challenges

There were a couple things that needed to be considered before I went ahead with this project.  First, is how to expand the data storage for the Nextcloud instance.  I had already expanded the block volume for my current instance twice, and I imagine it will continue to grow.  I was happy to find out that as of Kubernetes 1.11, expanding persistent volume claims was supported on most of the cloud providers.  Digital Ocean was not listed specifically in the article I read; however, the article was from before Digital Ocean had their hosted Kubernetes service.  This will need to be tested before I start moving data.

Second, was a question about how to backup my current data and move it to the kubernetes instance.  I don't have enough extra storage available on my current Nextcloud droplet to tar up the data directory.  I could add another block disk, copy the data there, then scp it back to my laptop, but that would be pretty slow download and subsequent upload.  A bit of searching found the [rclone project.](https://rclone.org/)  This program allows you to sync a directory to s3 compatible object storage. This will work to Digital Ocean Spaces, then I can download it directly to the container using the same tool.

## A Project for Another Day

Well, this project ended before it began.  While I was testing the storage resize challenge listed above, I found that this is not yet possible on Digital Ocean.  They have a GitHub [issue](https://github.com/digitalocean/csi-digitalocean/issues/106) open for it, and are waiting for an external resizer to be implemented within Kubernetes.

I had started writing this post, and instead of scrapping it entirely, I'm still going to post it.  First because sometimes its important to show what doesn't work, and because I will most likely update it when the feature is available.  This is also a reminder to me to make sure to test things before I jump in. I will note that this is possible on GKE or AKS, but I'm not going to stand up another cluster just for this.
