#!/bin/sh

# https://www.logilab.org/blogentry/114769
# https://github.com/tparker00/Openstack-ZFS

exit 0 # Not yet..
set -ex

if [ ! -e /usr/share/openstack-pkg-tools/pkgos_func ]; then
    echo "ERROR: openstack-pkg-tools not installed"
    exit 1
fi

. /usr/share/openstack-pkg-tools/pkgos_func
export PKGOS_VERBOSE=yes

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
#zfs: CommandFilter, /sbin/zfs, root
EOF

cat <<EOF >> /etc/cinder/cinder.conf

# ZFS/ZoL driver - https://github.com/tparker00/Openstack-ZFS
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
san_private_key=/etc/nova/sshkey
use_cow_images=false
san_zfs_command=/usr/local/sbin/zfswrapper
verbose=true
EOF

backends="$(grep '^enabled_backends' /etc/cinder/cinder.conf | sed 's@[ \t].*@@')"
[ -n "${backends}" ] && backends="${backends},"
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT enabled_backends ${backends}zol
for init in /etc/init.d/cinder-*; do $init restart; done

# Get the Cinder ZFS/ZoL ssh keys to use with ZFS/ZoL SAN.
curl -s http://${LOCALSERVER}/PXEBoot/var/www/PXEBoot/id_rsa-control > /etc/nova/sankey
chown nova /etc/nova/sankey
