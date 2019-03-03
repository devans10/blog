+++
title = "Moving from Dropbox to Nextcloud"
date = "2018-08-19T00:00:00Z"
draft = false
tags = ["nextcloud"]
+++

Last week I got a notification on my desktop that as of November 7, 2018 Dropbox will stop syncing files to my computer.  They are making a change to only support the “most popular filesystems”, and on Linux that means only unencrypted ext4.  Unfortunately, I use XFS on all of my machines, and I don't feel like duct taping solution together.  Besides, I have been looking for a reason to move off of Dropbox, and this just gave  me the push to move forward.

I’m not a huge Dropbox user, but it does serve a purpose for me.  I use it to sync some files between my phone and computers, and I will do the occasional sharing of files via links.  In addition, I have been looking for a good solution to sync photos from my wife's phone to a central location, since she will *never* do it herself.

So, it's time to look at NextCloud again and in a more serious manner.  I have played around with OwnCloud/NextCloud in the past.  Mainly just on my local LAN, running off of my FreeNAS.  However, now I’m going to want to have a setup that is available all the time, and that can be a Dropbox replacement, which means available over the internet.

## The Plan
My plan is to install NextCloud on a Digital Ocean droplet, and attach 100GB of Block Storage for the data.  I’m also going to need a DNS domain.  I have had some in the past, but have let them all expire, as I was never really happy with what I ended up with.  Lucky for me, a quick look on Google Domains shows that daveevans.us is available (as you know, since you're here).  It is not easy to find a “normal” top level domain with a common name such as mine.  I think I finally found a domain that I will stick with for awhile. (Hence, restarting my blog.)

---

I start by creating a 1 CPU, 1GB RAM, 25GB SSD Droplet on Digial Ocean with Ubuntu 18.04, attach my SSH key, create a 100GB Block Storage volume, and I’m off and away.  

Now that I have my machine, I do some quick hardening.
- Install fail2ban
- Setup my firewall
- Create an unpriviledged user and copy my SSH Key
- Remove root login via SSH
- Allow SSH login by only my unpriviledged user

Next, I look at the [NextCloud installation guide](https://www.digitalocean.com/community/tutorials/how-to-install-and-configure-nextcloud-on-ubuntu-18-04) from Digital Ocean. They have a snap package, which should make things very easy. 

```bash
snap install nextcloud
sudo nextcloud.manual-install <username> <password>
sudo nextcloud.occ config:system:set trusted_domains 1 --value=example.com
sudo ufw allow 80,443/tcp
sudo nextcloud.enable-https lets-encrypt
```

That was easy, except…

I go to login to the NextCloud web console, and my password does not work.  So I find out how to change a lost admin password.

```bash
sudo nextcloud.occ user:resetpassword <username>
```

Alright, now I can login. 

Next, I want to move the data directory to the Block Storage that I setup.  I create a logical volume with the block storage and mount it at /data.

For this move, I have to change the ‘datadirectory’ parameter in the /var/snap/nextcloud/current/nextcloud/config/config.php file to point to /data. Then, stop the applicaton, move the data, and restart.

```bash
sudo snap disable nextcloud
sudo mv /var/snap/nextcloud/common/nextcloud/data /data
sudo snap enable nextcloud
```

...and everything breaks.

It turns out that NextCloud installed via snap package, cannot access any directories outside the snap.  This actually makes sense, since snaps are sandboxed applications.  Maybe there is a way to allow this, but I’m still pretty new to snaps and don’t feel like researching it right now.  I give a quick try to outsmart technology, and mount my data disk at /var/snap/nextcloud/common/nextcloud/data. That fixes nothing.  Its back to the drawing board.

---

So, the manual install it is…

I followed the [NextCloud Installation Guide](https://docs.nextcloud.com/server/13/admin_manual/installation/source_installation.html) for this install. It was pretty straight forward, but did have a couple different options to pick from.

I chose to use php7.2, mariadb, and apache, since those are what I’m most familiar with.  There is a long list of php prerequisites that are listed in the Install Guide, but a lot of them actually get installed with some of the higher level packages.

```bash
apt-get install apache2 mariadb-server libapache2-mod-php7.2
apt-get install php7.2-gd php7.2-json php7.2-mysql php7.2-curl php7.2-mbstring
apt-get install php7.2-intl php7.2-mcrypt php-imagick php7.2-xml php7.2-zip
```

Next, run the mysql secure install script.
```bash
sudo mysql_secure_installation
```

There are some settings that need to be changed in the php.ini

```bash
vi /etc/php/7.2/apache2/php.ini
```
```
file_uploads = On
allow_url_fopen = On
memory_limit = 256M
upload_max_filesize = 100M
display_errors = Off
date.timezone = America/New_York
```

Now, I can create the nextcloud database.
```bash
sudo mysql -u root -p
CREATE DATABASE nextcloud;
CREATE USER 'nextcloud'@'localhost' IDENTIFIED BY '<password>';
GRANT ALL ON nextcloud.* TO 'nextcloud'@'localhost' IDENTIFIED BY '<password>' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EXIT;
```

Create an apache website configuration file.
```bash
vi /etc/apache2/sites-available/nextcloud.conf
```

```
Alias / "/var/www/nextcloud/"

<Directory /var/www/nextcloud/>
  Options +FollowSymlinks
  AllowOverride All

 <IfModule mod_dav.c>
  Dav off
 </IfModule>

 SetEnv HOME /var/www/nextcloud
 SetEnv HTTP_HOME /var/www/nextcloud

</Directory>
```

And, create a soft link to it in the sites-enabled directory. Then enable some Apache modules, and restart apache.
```bash
ln -s /etc/apache2/sites-available/nextcloud.conf /etc/apache2/sites-enabled//nextcloud.conf
a2enmod rewrite
a2enmod env
a2enmod dir
a2enmod mime
a2enmod setenvif
systemctl restart apache2
```

Now we have to download the nextcloud ZIP file.  At this time 13.0.5 is the latest release.
```bash
cd /var/www
wget https://download.nextcloud.com/server/releases/nextcloud-13.0.5.zip
unzip nextcloud-13.0.5.zip

systemctl restart apache2
```

That was pretty painless.

Next, I login to the Web Console for the setup wizard.  Here I enter my username/password, and I’m able to specify my data storage directory as /data.  Then enter the database details, and the setup completes. Everything is working again, and I’m able to see the 100GB of storage

## Data Migration From Dropbox

Moving off of Dropbox is the easy part.  As I said, I’m not a big Dropbox user, and have less than 1GB of data stored there. 

I install the NextCloud Client using the snap package.
```bash
sudo snap install nextcloud-client
```

I start the client application and login to my instance.  The dialogue box give me an option to login with an app password.  In the web console, under my user settings → security, there is an option to create an App Password.  I do this and copy the app password into the dialogue box.  I’m able to specify a new folder to sync NextCloud to, so I create NextCloud under my home directory.  The default location was in the snap location, so I wasn’t sure if this was going to work because of the issue I had on the server.  I got no errors, and everything seems to be working fine.  

I then copy the files from my Dropbox folder to NextCloud and everything syncs as I expect.


## Move Pictures from iCloud

For years now, My wife and I have uploaded pictures from our iPhones to iCloud.  I have just under 5000 photos, my wife has about 10,000.  I’m going to test out on just myself first. 

As a side note, we have been sending pictures to iCloud, but I also keep a local backup copy on my FreeNAS server. Which I painstakingly sync from iCloud every couple months.  I’m hoping with the NextCloud setup I can sync to my FreeNAS with this setup. But that is for a future post.

I already had the NextCloud App on my iPhone. I try to login to my new instance using an App Password like I did on my desktop, but it just sits there and spins. So I change to login with my user ID, which I’ll probably regret later.

The app has a setting to copy my whole Photo Library and organize them into folders by year and month.  I turn it on and it starts sending ~5000 photos to NextCloud.

I quickly figure out that even though I flip the switch to allow the application to run in the backgroup, photos do not upload if the app is not in the foreground.  Luckily, by this time, I’m just about ready to call it a night. So I set my phone to Never Lock, and let it run over night.  

By morning the sync is finished.  I’m going to let this run for a couple weeks before I attempt my wife’s phone.

### UPDATE
Not everything actually synced over.  Most of it did, but I do have about 800 images that didn't make it.  I will probably do a follow-up post just on data migration.

[Next post on my cloud migration](/posts/migration-to-nextcloud-part-2/)
