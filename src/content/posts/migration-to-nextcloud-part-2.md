+++
title = "Migrating to NextCloud, Part 2"
date = "2018-08-24T00:00:00Z"
draft = false
tags = ["nextcloud"]
+++

[Previous Post](/posts/moving-from-dropbox-to-nextcloud/)

As I found out shortly after my last post about migrating to NextCloud. Not all of my data transferred successfully.  However, this was not NextClouds fault.  The short version is that I was allowing the NextCloud iOS client to upload my photos through my iPhone.  The problem happened as the original(aka, non-optimized) photos were downloaded from iCloud then uploaded to NextCloud. As more photos came down, I ran out of space on my iPhone.

So now I was in a dilemma, I do not have enough hard drive space on my 2010 Macbook Pro to handle the photos. iCloud does not offer a good way to download bulk photos via their web console, and there is no application for Linux.

### Python to the rescue
Really, [This guy](https://github.com/picklepete/pyicloud) to the rescue.  PicklePete on github did pretty much all the heavy lifting on this one.  PyiCoud is a python library written to interact with iCloud via Python.  It even handles 2-factor authentication.  So using his library, I was able to write a script to download all my photos and sort them into directories by year and month.  I ran this on a 4 CPU, 8GB DigitalOcean droplet.  The process took about 20 minutes.

After running the download from iCloud, which was done on a separate machine from my NextCloud instance.  I just used rsync to copy the files to my NextCloud server. When the copy is complete I need to execute the command below to rescan all the files and pull them into NextCloud.
```bash
chown -R www-data:www-data /data
sudo -u www-data php /var/www/nextcloud/occ files:scan --all
```

Here is the script that I used to download all my photos from iCloud.
[Next Cloud Migration](https://gitlab.com/devans10/NextCloudMigration/)

##### Next Post
[Using QOwnNotes with NextCloud](http://www.daveevans.us/2018/08/26/using-qownnotes-with-nextcloud/)
