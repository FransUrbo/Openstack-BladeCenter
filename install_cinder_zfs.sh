#!/bin/sh

exit 0 # Not yet..
set -ex

# Get the Cinder-ZFS/ZoL plugin
curl -s https://raw.githubusercontent.com/tparker00/Openstack-ZFS/master/zol.py > \
    /usr/lib/python2.7/dist-packages/cinder/volume/zol.py

# Get the ZFS/ZoL wrapper (?)
curl -s http://${LOCALSERVER}/PXEBoot/var/www/PXEBoot/zfswrapper > \
    /usr/local/sbin/zfswrapper
chmod +x /usr/local/sbin/zfswrapper

# Update Cinder configuration files
cat <<EOF >> /etc/cinder/rootwrap.d/volume.filters

# ZFS/ZoL plugin
#zfs: CommandFilter, /sbin/zfs, root
EOF

cat <<EOF >> /etc/cinder/cinder.conf

[zol]
volume_driver=cinder.volume.zol.ZFSonLinuxISCSIDriver
volume_group=share/BladeCenter
iscsi_ip_prefix=192.168.69.8
iscsi_ip_address=${ip}
san_thin_provision=false
san_ip=${ip}
san_zfs_volume_base=share/BladeCenter
san_is_local=false
san_login=root
san_private_key=/etc/nova/sankey
use_cow_images=false
san_zfs_command=/usr/local/sbin/zfswrapper
verbose=true
EOF

sed -i "s@^\(enabled_backends[ \t]=.*\)@\1, zol" /etc/cinder/cinder.conf
for init in /etc/init.d/cinder-*; do $init restart; done

# Get the Cinder ZFS/ZoL ssh keys to use with ZFS/ZoL SAN.
curl -s http://${LOCALSERVER}/PXEBoot/var/www/PXEBoot/id_rsa-control > /etc/nova/sankey
chown nova /etc/nova/sankey
