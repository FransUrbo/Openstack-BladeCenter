#!/bin/sh

# https://wiki.openstack.org/wiki/Docker

do_install() {
    apt-get -y --no-install-recommends install $*
}

curl -s http://${LOCALSERVER}/PXEBoot/openstack-configure > \
    /usr/local/bin/openstack-configure
chmod +x /usr/local/bin/openstack-configure

set -ex

# Install the support packages for Nova-Docker
do_install docker.io python-pip git aufs-tools

# Prepare for Nova/docker
usermod -aG docker nova

# Install Nova/docker
cd /tmp
pip install -e git+https://github.com/stackforge/nova-docker#egg=novadocker
cd src/novadocker/
echo "GIT $(git log | head -n1)"
python setup.py install

# Update Nova config
openstack-configure set /etc/nova/nova-compute.conf DEFAULT compute_driver novadocker.virt.docker.DockerDriver
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
inject_key = true
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

# Get all my special Docker images.
if ! glance image-list | grep -q fransurbo; then
    # Only do this once, on the first ever Compute..
    docker images fransurbo/devel | \
        grep -v "TAG" | \
        while read line; do
	    set -- $(echo "${line}")
            tag="${2}"

            docker pull "fransurbo/devel:${tag}"
            docker save "fransurbo/devel:${tag}" | \
                glance image-create --container-format=docker --disk-format=raw \
		    --property protected=True --name "fransurbo/devel:${tag}"
    done
fi

