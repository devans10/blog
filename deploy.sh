#!/bin/sh

cd ./src
/usr/bin/hugo
/usr/bin/rsync -a public/* root@www.daveevans.us:/var/www/www.daveevans.us/
/usr/bin/ssh root@www.daveevans.us /usr/bin/systemctl reload apache2

/usr/bin/rm -rf ./public