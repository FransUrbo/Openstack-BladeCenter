#!/bin/sh

# https://www.logilab.org/blogentry/114769
# https://github.com/tparker00/Openstack-ZFS

# TODO:
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume [req-a5eb2668-861f-4106-a6da-26f4ec7d41f5 - - - - -] Volume service bladeA01b@zol failed to start.
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume Traceback (most recent call last):
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume   File "/usr/lib/python2.7/dist-packages/cinder/cmd/volume.py", line 81, in main
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume     binary='cinder-volume')
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume   File "/usr/lib/python2.7/dist-packages/cinder/service.py", line 263, in create
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume     service_name=service_name)
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume   File "/usr/lib/python2.7/dist-packages/cinder/service.py", line 134, in __init__
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume     *args, **kwargs)
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume   File "/usr/lib/python2.7/dist-packages/cinder/volume/manager.py", line 284, in __init__
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume     active_backend_id=curr_active_backend_id)
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume   File "/usr/lib/python2.7/dist-packages/oslo_utils/importutils.py", line 44, in import_object
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume     return import_class(import_str)(*args, **kwargs)
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume   File "/usr/lib/python2.7/dist-packages/oslo_utils/importutils.py", line 30, in import_class
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume     __import__(mod_str)
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume   File "/usr/lib/python2.7/dist-packages/cinder/volume/zol.py", line 32, in <module>
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume     from cinder import flags
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume ImportError: cannot import name flags
# 2016-06-23 12:55:39.129 13819 ERROR cinder.cmd.volume

if [ ! -e "/root/admin-openrc" ]; then
    echo "The /root/admin-openrc file don't exists."
    exit 1
else
    set +x # Disable showing commands this do (password especially).
    . /root/admin-openrc
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

# Get the Cinder-ZFS/ZoL plugin
#curl -s https://raw.githubusercontent.com/tparker00/Openstack-ZFS/master/zol.py > \
curl -s http://${LOCALSERVER}/PXEBoot/nova-zol.py-tparker+mariocar > \
    /usr/lib/python2.7/dist-packages/cinder/volume/drivers/zol.py

# Update Cinder configuration files
cat <<EOF >> /etc/cinder/rootwrap.d/volume.filters

# ZFS/ZoL plugin
zfs: CommandFilter, /sbin/zfs, root
EOF

cat <<EOF >> /etc/cinder/cinder.conf

# ZFS/ZoL driver - https://github.com/tparker00/Openstack-ZFS
[zol]
volume_driver = cinder.volume.drivers.zol.ZFSonLinuxISCSIDriver
volume_group = share/VirtualMachines/Blade_Center
volume_backend_name = ZFS_iSCSI
iscsi_ip_prefix = 192.168.69.8
san_thin_provision = false
san_ip = ${ip}
san_zfs_volume_base = share/VirtualMachines/Blade_Center
san_is_local = false
san_login = root
san_private_key = /etc/nova/sshkey
use_cow_images = false
san_zfs_command = /var/www/PXEBoot/zfswrapper
verbose = true
EOF

TODO: !! See the top of the file !!
#OLD="$(openstack-configure get /etc/cinder/cinder.conf DEFAULT enabled_backends)"
#openstack-configure set /etc/cinder/cinder.conf DEFAULT enabled_backends "${OLD:+${OLD},}zol"
#for init in /etc/init.d/cinder-*; do $init restart; done
#openstack volume type create --description "ZFS volumes" --public zfs
#openstack volume type set --property volume_backend_name=ZFS_iSCSI zfs

# Get the Cinder ZFS/ZoL ssh keys to use with ZFS/ZoL SAN.
curl -s http://${LOCALSERVER}/PXEBoot/var/www/PXEBoot/id_rsa-control > /etc/nova/sankey
chown nova /etc/nova/sankey
