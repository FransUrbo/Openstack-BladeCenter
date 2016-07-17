#!/bin/sh

# https://www.logilab.org/blogentry/114769
# https://github.com/tparker00/Openstack-ZFS
# https://github.com/FransUrbo/Openstack-ZFS

do_install() {
    apt-get -y --no-install-recommends install $*
}

if [ ! -e "/root/admin-openrc" ]; then
    echo "The /root/admin-openrc file don't exists."
    exit 1
else
    set +x # Disable showing commands this do (password especially).
    . /root/admin-openrc
    if [ -z "${OS_AUTH_URL}" ]; then
        echo "Something wrong with the admin-openrc!"
        exit 1
    fi
fi

set -xe

if [ ! -e "/usr/local/bin/openstack-configure" ]; then
    curl -s http://${LOCALSERVER}/PXEBoot/openstack-configure > \
        /usr/local/bin/openstack-configure
    chmod +x /usr/local/bin/openstack-configure
fi

# Get IP of this host
set -- $(/sbin/ip address | egrep " eth.* UP ")
iface="$(echo "${2}" | sed 's@:@@')"
set -- $(/sbin/ifconfig "${iface}" | grep ' inet ')
ip="$(echo "${2}" | sed 's@.*:@@')"

# Get the hostname. This is the simplest and fastest.
hostname="$(cat /etc/hostname)"

# ======================================================================
# Install the support packages for Openstack-ZFS
do_install git

# ======================================================================
# Get the Cinder-ZFS/ZoL plugin
cd /usr/src
git clone https://github.com/FransUrbo/Openstack-ZFS.git
cp zol.py /usr/lib/python2.7/dist-packages/cinder/volume/drivers/
pycompile /usr/lib/python2.7/dist-packages/cinder/volume/drivers/zol.py

# ======================================================================
# Update Cinder configuration files
cat <<EOF >> /etc/cinder/rootwrap.d/volume.filters

# ZFS/ZoL plugin
zfs: CommandFilter, /sbin/zfs, root
EOF

cat <<EOF >> /etc/cinder/cinder.conf

# ZFS/ZoL driver - https://github.com/FransUrbo/Openstack-ZFS.git
[zol]
volume_driver = cinder.volume.drivers.zol.ZFSonLinuxISCSIDriver
volume_backend_name = ZOL

san_zfs_volume_base = share/VirtualMachines/Blade_Center
san_zfs_compression = lz4
san_zfs_checksum = sha256
zol_max_over_subscription_ratio = 4.0

san_is_local = false
san_ip = 192.168.69.8
san_login = root
san_private_key = /etc/cinder/sshkey
san_thin_provision = true

ssh_conn_timeout = 15

verbose = true
debug = true
EOF

OLD="$(openstack-configure get /etc/cinder/cinder.conf DEFAULT enabled_backends)"
openstack-configure set /etc/cinder/cinder.conf DEFAULT enabled_backends "${OLD:+${OLD},}zol"
for init in /etc/init.d/cinder-*; do $init restart; done

# ======================================================================
# Create host aggregate.
openstack aggregate create --zone nova --property volume_backend_name=ZOL zfs

# ======================================================================
# Create volume type.
openstack volume type create --description "ZFS volumes" --public zfs
openstack volume type set --property volume_backend_name=ZOL zfs

# ======================================================================
# Create flavors.
openstack flavor create --ram   512 --disk  2 --vcpus 1 --disk  5 z1.1nano
openstack flavor create --ram  1024 --disk 10 --vcpus 1 --disk  5 z1.2tiny
openstack flavor create --ram  2048 --disk 20 --vcpus 1 --disk 10 z1.3small
openstack flavor create --ram  4096 --disk 40 --vcpus 1 z1.4medium
openstack flavor create --ram  8192 --disk 40 --vcpus 1 z1.5large
openstack flavor create --ram 16384 --disk 40 --vcpus 1 z1.6xlarge

openstack flavor create --ram  1024 --disk 10 --vcpus 2 --disk 5 z2.1tiny
openstack flavor create --ram  2048 --disk 20 --vcpus 2 z2.2small
openstack flavor create --ram  4096 --disk 40 --vcpus 2 z2.3medium
openstack flavor create --ram  8192 --disk 40 --vcpus 2 z2.4large
openstack flavor create --ram 16384 --disk 40 --vcpus 2 z2.5xlarge

openstack flavor create --ram  1024 --disk 20 --vcpus 3 --disk  5 z3.1tiny
openstack flavor create --ram  2048 --disk 20 --vcpus 3 --disk 10 z3.2small
openstack flavor create --ram  4096 --disk 40 --vcpus 3 z3.3medium
openstack flavor create --ram  8192 --disk 40 --vcpus 3 z3.4large
openstack flavor create --ram 16384 --disk 40 --vcpus 3 z3.5xlarge

openstack flavor create --ram  1024 --disk 10 --vcpus 4 --disk  5 z4.1tiny
openstack flavor create --ram  2048 --disk 20 --vcpus 4 --disk 10 z4.2small
openstack flavor create --ram  4096 --disk 40 --vcpus 4 z4.3medium
openstack flavor create --ram  8192 --disk 40 --vcpus 4 z4.4large
openstack flavor create --ram 16384 --disk 40 --vcpus 4 z4.5xlarge

openstack flavor list --all --column Name --format csv --quote none | \
    grep ^z | \
    while read flavor; do
	openstack flavor set --property volume_backend_name=ZOL "${flavor}"
    done
