#!/bin/sh

# https://wiki.openstack.org/wiki/Docker

do_install() {
    apt-get -y --no-install-recommends install $*
}

if [ ! -e /usr/share/openstack-pkg-tools/pkgos_func ]; then
    echo "ERROR: openstack-pkg-tools not installed"
    exit 1
else
    . /usr/share/openstack-pkg-tools/pkgos_func
    export PKGOS_VERBOSE=yes
fi

set -ex

# Install the support packages for Nova-Docker
do_install docker.io python-pip git aufs-tools

# Prepare for Nova/docker
usermod -aG docker nova

# Install Nova/docker
cd /tmp
pip install -e git+https://github.com/stackforge/nova-docker#egg=novadocker
cd src/novadocker/
python setup.py install

# Update Nova config
pkgos_inifile set /etc/nova/nova-compute.conf DEFAULT compute_driver novadocker.virt.docker.DockerDriver
mkdir -p /etc/nova/rootwrap.d
cat <<EOF > /etc/nova/rootwrap.d/docker.filters
# nova-rootwrap command filters for setting up network in the docker driver
# This file should be owned by (and only-writeable by) the root user
# git+https://github.com/stackforge/nova-docker#egg=novadocker

[Filters]
# nova/virt/docker/driver.py: 'ln', '-sf', '/var/run/netns/.*'
ln: CommandFilter, /bin/ln, root
EOF
cat <<EOF >> /etc/nova/nova-compute.conf

# Nova Docker driver
[docker]
compute_driver = novadocker.virt.docker.DockerDriver
EOF
for init in /etc/init.d/nova-*; do $init restart; done

# Remove git and pip - don't need or want it any more.
apt-get -y remove python-pip git
rm -Rf /tmp/src

# Make sure Docker start correctly.
echo "" >> /etc/default/docker
echo "DOCKER_OPTS=\"-H fd:// -H unix:///var/run/docker.sock -H tcp://127.0.0.1:2375\"" \
    >> /etc/default/docker
/etc/init.d/docker restart

# Get all my Docker images. Use nohup and in the background,
# because this takes quite a while!
for tag in centos5 centos6 centos7 fedora20 fedora21 \
    fedora22 fedora23 jessie sid trusty utopic vivid \
    wheezy wily xenial
do
    nohup docker pull fransurbo/devel:$tag &
done
