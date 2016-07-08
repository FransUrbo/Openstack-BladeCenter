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
cd /usr/src
pip install -e git+https://github.com/stackforge/nova-docker#egg=novadocker nova-docker
cd nova-docer/novadocker/
echo "GIT $(git log | head -n1)"
python setup.py install
cd /root

# Update Nova config
cp /etc/nova/nova-compute.conf /etc/nova/nova-compute.conf.orig
# TODO: "ERROR nova.virt.driver ImportError: No module named netconf"
#openstack-configure set /etc/nova/nova-compute.conf DEFAULT compute_driver novadocker.virt.docker.DockerDriver
openstack-configure set /etc/nova/nova-compute.conf DEFAULT compute_driver nova.virt.libvirt.LibvirtDriver
openstack-configure set /etc/nova/nova-compute.conf DEFAULT use_virtio_for_bridges true

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
#images_volume_group = <local_lvm_group>

# Nova Docker driver
[docker]
compute_driver = novadocker.virt.docker.DockerDriver
#vif_driver = novadocker.virt.docker.vifs.DockerGenericVIFDriver
snapshots_directory = /var/lib/docker/tmp
inject_key = true
EOF
for init in /etc/init.d/nova-*; do $init restart; done

# Remove git and pip - don't need or want it any more.
apt-get -y remove python-pip git

# Make sure Docker start correctly.
echo "" >> /etc/default/docker
echo "DOCKER_OPTS=\"-H fd:// -H unix:///var/run/docker.sock -H tcp://127.0.0.1:2375\"" \
    >> /etc/default/docker
/etc/init.d/docker restart

GENERAL_OPTS="--public --protected
--project admin
--disk-format raw
--container-format docker
--property architecture=x86_64
--property hypervisor_type=docker"

# Get all my special Docker images.
docker images fransurbo/devel | \
    grep -v "TAG" | \
    while read line; do
	set -- $(echo "${line}")
        tag="${2}"

        # We need that on each Docker host.
        docker pull "fransurbo/devel:${tag}"

        if ! glance image-list | grep -q "fransurbo/devel:${tag}"
        then
            # .. but this only once in Glance.
            docker save "fransurbo/devel:${tag}" | \
                openstack image create ${GENERAL_OPTS} \
                    --property os_command_line='/usr/sbin/sshd -D' \
                    "fransurbo/devel:${tag}"
        fi
    done

docker pull busybox
docker tag busybox fransurbo/devel:busybox
docker rmi busybox
if ! glance image-list | grep -q fransurbo; then
    docker save "fransurbo/devel:busybox" | \
        openstack image create ${GENERAL_OPTS} \
            --property os_command_line='/usr/sbin/sshd -D' \
            "fransurbo/devel:busybox"
fi

