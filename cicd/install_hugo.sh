!#/usr/bin/env bash

HUGO_VERSION=0.88.1
wget https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz
tar -xf hugo_extended_${HUGO_VERSION}_Linux-64bit.tar.gz -C /usr/local/bin/