#!/bin/sh

do_install() {
    apt-get -y --no-install-recommends install $*
}

set -ex

# Install the support packages for Nova-Docker
do_install docker.io python-pip git

# Prepare for Nova/docker
usermod -aG docker nova

# Install Nova/docker
cd /tmp
pip install -e git+https://github.com/stackforge/nova-docker#egg=novadocker
cd src/novadocker/
python setup.py install

# Update Nova config
sed -i "s@^#compute_driver.*@compute_driver = novadocker.virt.docker.DockerDriver@" /etc/nova/nova.conf
mkdir -p /etc/nova/rootwrap.d
cat <<EOF > /etc/nova/rootwrap.d/docker.filters
# nova-rootwrap command filters for setting up network in the docker driver
# This file should be owned by (and only-writeable by) the root user
# git+https://github.com/stackforge/nova-docker#egg=novadocker

[Filters]
# nova/virt/docker/driver.py: 'ln', '-sf', '/var/run/netns/.*'
ln: CommandFilter, /bin/ln, root
EOF
for init in /etc/init.d/nova-*; do $init restart; done

# Remove git and pip - don't need or want it any more.
apt-get -y remove python-pip git
rm -Rf /tmp/src
