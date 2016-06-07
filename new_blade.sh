#!/bin/sh

set -ex

# Get the basic setup files (ssh/gpg keys etc)
cd /var/tmp
wget http://localserver/new_blade.tgz
cd /

# Unpack the basic setup files
tar xvzf /var/tmp/new_blade.tgz

# Make sure we can login as root
sed -i "s@^PermitRootLogin@#PermitRootLogin@" /etc/ssh/sshd_config

# Install core++ packages
sh /var/tmp/install
