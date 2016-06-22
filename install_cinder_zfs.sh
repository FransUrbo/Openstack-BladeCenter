#!/bin/sh

# https://www.logilab.org/blogentry/114769
# https://github.com/tparker00/Openstack-ZFS

exit 0 # Not yet..

if [ ! -e "admin-openrc" ]; then
    echo "The admin-openrc file don't exists."
    exit 1
else
    set +x # Disable showing commands this do (password especially).
    . /root/admin-openrc
fi

curl -s http://${LOCALSERVER}/PXEBoot/openstack-configure > \
    /usr/local/bin/openstack-configure
chmod +x /usr/local/bin/openstack-configure

set -xe

# Get IP of this host
set -- $(/sbin/ip address | egrep " eth.* UP ")
iface="$(echo "${2}" | sed 's@:@@')"
set -- $(/sbin/ifconfig "${iface}" | grep ' inet ')
ip="$(echo "${2}" | sed 's@.*:@@')"

# Get the hostname. This is the simplest and fastest.
hostname="$(cat /etc/hostname)"

# ======================================================================

# Get the Cinder-ZFS/ZoL plugin
#curl -s https://raw.githubusercontent.com/tparker00/Openstack-ZFS/master/zol.py > \
curl -s http://${LOCALSERVER}/PXEBoot/nova-zol.py-tparker+mariocar > \
    /usr/lib/python2.7/dist-packages/cinder/volume/zol.py

# Get the ZFS/ZoL wrapper - ?? On the SAN server or here ??
curl -s http://${LOCALSERVER}/PXEBoot/zfswrapper > \
    /usr/local/sbin/zfswrapper
chmod +x /usr/local/sbin/zfswrapper

# Update Cinder configuration files
cat <<EOF >> /etc/cinder/rootwrap.d/volume.filters

# ZFS/ZoL plugin
zfs: CommandFilter, /sbin/zfs, root
EOF

cat <<EOF >> /etc/cinder/cinder.conf

# ZFS/ZoL driver - https://github.com/tparker00/Openstack-ZFS
[zol]
volume_driver = cinder.volume.zol.ZFSonLinuxISCSIDriver
volume_group = share/VirtualMachines/Blade_Center
volume_backend_name = ZFS_iSCSI
iscsi_ip_prefix = 192.168.69.8
iscsi_ip_address = ${ip}
san_thin_provision = false
san_ip = ${ip}
san_zfs_volume_base = share/VirtualMachines/Blade_Center
san_is_local = false
san_login = root
san_private_key = /etc/nova/sshkey
use_cow_images = false
san_zfs_command = /usr/local/sbin/zfswrapper
verbose = true
EOF

OLD="$(openstack-configure get /etc/cinder/cinder.conf DEFAULT enabled_backends)"
[ -n "${OLD}" ] && OLD="${OLD},"
openstack-configure set /etc/cinder/cinder.conf DEFAULT enabled_backends "${OLD}zol"
for init in /etc/init.d/cinder-*; do $init restart; done
openstack volume type create --description "ZFS volumes" --public zfs
openstack volume type set --property volume_backend_name=ZFS_iSCSI zfs

# Get the Cinder ZFS/ZoL ssh keys to use with ZFS/ZoL SAN.
curl -s http://${LOCALSERVER}/PXEBoot/var/www/PXEBoot/id_rsa-control > /etc/nova/sankey
chown nova /etc/nova/sankey
