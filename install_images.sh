#!/bin/sh

set -xe

# Import a bunch of external images.
# http://docs.openstack.org/image-guide/obtain-images.html
# http://docs.openstack.org/cli-reference/glance.html

if [ ! -e "/root/admin-openrc" ]; then
    echo "The admin-openrc file don't exists."
    exit 1
else
    set +x
    . /root/admin-openrc
fi

set -x

GENERAL_OPTS="--public --protected
--project admin
--disk-format qcow2
--container-format docker
--property architecture=x86_64
--property hypervisor_type=kvm
--property hw_watchdog_action=reset"

mkdir -p /var/tmp/Images
cd /var/tmp/Images

# Find out minimum disk size:
#   bladeA01b:/var/tmp/Images# qemu-img info CentOS-6-x86_64-GenericCloud-1605.qcow2 | grep 'virtual size'
#   virtual size: 8.0G (8589934592 bytes)
# Then round up to nearest GB (in this case '9').

if [ ! -e "CentOS-6-x86_64-GenericCloud-1605.qcow2" ]; then
    #wget --quiet http://cloud.centos.org/centos/6/images/CentOS-6-x86_64-GenericCloud-1605.qcow2 
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/CentOS-6-x86_64-GenericCloud-1605.qcow2 
    openstack image create ${GENERAL_OPTS} --min-disk 9 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=centos --property os_version=6 \
        --file CentOS-6-x86_64-GenericCloud-1605.qcow2 centos6
fi

if [ ! -e "CentOS-7-x86_64-GenericCloud-1605.qcow2" ]; then
    #wget --quiet http://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud-1605.qcow2
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/CentOS-7-x86_64-GenericCloud-1605.qcow2
    openstack image create ${GENERAL_OPTS} --min-disk 9 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=centos --property os_version=7 \
        --file CentOS-7-x86_64-GenericCloud-1605.qcow2 centos7
fi

if [ ! -e "cirros-0.3.4-x86_64-disk.img" ]; then
    #wget --quiet http://download.cirros-cloud.net/0.3.4/cirros-0.3.4-x86_64-disk.img
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/cirros-0.3.4-x86_64-disk.img
    openstack image create ${GENERAL_OPTS} --min-disk 1 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --file cirros-0.3.4-x86_64-disk.img cirros
fi

if [ ! -e "trusty-server-cloudimg-amd64-disk1.img" ]; then
    #wget --quiet http://cloud-images.ubuntu.com/trusty/current/trusty-server-cloudimg-amd64-disk1.img
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/trusty-server-cloudimg-amd64-disk1.img
    openstack image create ${GENERAL_OPTS} --min-disk 3 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=ubuntu --property os_version=14.04 \
        --file trusty-server-cloudimg-amd64-disk1.img trusty
fi

if [ ! -e "precise-server-cloudimg-amd64-disk1.img" ]; then
    #wget --quiet http://cloud-images.ubuntu.com/precise/current/precise-server-cloudimg-amd64-disk1.img
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/precise-server-cloudimg-amd64-disk1.img
    openstack image create ${GENERAL_OPTS} --min-disk 3 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=ubuntu --property os_version=12.04 \
        --file precise-server-cloudimg-amd64-disk1.img precise
fi

if [ ! -e "quantal-server-cloudimg-amd64-disk1.img" ]; then
    #wget --quiet http://cloud-images.ubuntu.com/quantal/current/quantal-server-cloudimg-amd64-disk1.img
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/quantal-server-cloudimg-amd64-disk1.img
    openstack image create ${GENERAL_OPTS} --min-disk 3 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=ubuntu --property os_version=12.10 \
        --file quantal-server-cloudimg-amd64-disk1.img quantal
fi

if [ ! -e "raring-server-cloudimg-amd64-disk1.img" ]; then
    #wget --quiet http://cloud-images.ubuntu.com/raring/current/raring-server-cloudimg-amd64-disk1.img
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/raring-server-cloudimg-amd64-disk1.img
    openstack image create ${GENERAL_OPTS} --min-disk 3 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=ubuntu --property os_version=13.04 \
        --file raring-server-cloudimg-amd64-disk1.img raring
fi

if [ ! -e "saucy-server-cloudimg-amd64-disk1.img" ]; then
    #wget --quiet http://cloud-images.ubuntu.com/saucy/current/saucy-server-cloudimg-amd64-disk1.img
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/saucy-server-cloudimg-amd64-disk1.img
    openstack image create ${GENERAL_OPTS} --min-disk 3 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=ubuntu --property os_version=13.10 \
        --file saucy-server-cloudimg-amd64-disk1.img saucy
fi

if [ ! -e "utopic-server-cloudimg-amd64-disk1.img" ]; then
    #wget --quiet http://cloud-images.ubuntu.com/utopic/current/utopic-server-cloudimg-amd64-disk1.img
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/utopic-server-cloudimg-amd64-disk1.img
    openstack image create ${GENERAL_OPTS} --min-disk 3 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=ubuntu --property os_version=14.10 \
        --file utopic-server-cloudimg-amd64-disk1.img utopic
fi

if [ ! -e "vivid-server-cloudimg-amd64-disk1.img" ]; then
    #wget --quiet http://cloud-images.ubuntu.com/vivid/current/vivid-server-cloudimg-amd64-disk1.img
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/vivid-server-cloudimg-amd64-disk1.img
    openstack image create ${GENERAL_OPTS} --min-disk 3 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=ubuntu --property os_version=15.04 \
        --file vivid-server-cloudimg-amd64-disk1.img vivid
fi

if [ ! -e "wily-server-cloudimg-amd64-disk1.img" ]; then
    #wget --quiet http://cloud-images.ubuntu.com/wily/current/wily-server-cloudimg-amd64-disk1.img
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/wily-server-cloudimg-amd64-disk1.img
    openstack image create ${GENERAL_OPTS} --min-disk 3 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=ubuntu --property os_version=15.10 \
        --file wily-server-cloudimg-amd64-disk1.img wily
fi

if [ ! -e "xenial-server-cloudimg-amd64-disk1.img" ]; then
    #wget --quiet http://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/xenial-server-cloudimg-amd64-disk1.img
    openstack image create ${GENERAL_OPTS} --min-disk 3 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=ubuntu --property os_version=16.04 \
        --file xenial-server-cloudimg-amd64-disk1.img xenial
fi

if [ ! -e "yakkety-server-cloudimg-amd64.img" ]; then
    #wget --quiet http://cloud-images.ubuntu.com/yakkety/current/yakkety-server-cloudimg-amd64.img
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/yakkety-server-cloudimg-amd64.img
    openstack image create ${GENERAL_OPTS} --min-disk 3 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=ubuntu --property os_version=16.10 \
        --file yakkety-server-cloudimg-amd64.img yakkety
fi

if [ ! -e "Fedora-Cloud-Base-23-20151030.x86_64.qcow2" ]; then
    #wget --quiet https://download.fedoraproject.org/pub/fedora/linux/releases/23/Cloud/x86_64/Images/Fedora-Cloud-Base-23-20151030.x86_64.qcow2
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/Fedora-Cloud-Base-23-20151030.x86_64.qcow2
    openstack image create ${GENERAL_OPTS} --min-disk 4 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=fedora --property os_version=23 \
        --file Fedora-Cloud-Base-23-20151030.x86_64.qcow2 fedora23
fi

if [ ! -e "Fedora-Cloud-Base-22-20150521.x86_64.qcow2" ]; then
    #wget --quiet https://www.mirrorservice.org/sites/dl.fedoraproject.org/pub/fedora/linux/releases/22/Cloud/x86_64/Images/Fedora-Cloud-Base-22-20150521.x86_64.qcow2
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/Fedora-Cloud-Base-22-20150521.x86_64.qcow2
    openstack image create ${GENERAL_OPTS} --min-disk 4 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=fedora --property os_version=22 \
        --file Fedora-Cloud-Base-22-20150521.x86_64.qcow2 fedora22
fi

if [ ! -e "openSUSE-13.2-OpenStack-Guest.x86_64-0.0.10-Build2.77.qcow2" ]; then
    #wget --quiet http://download.opensuse.org/repositories/Cloud:/Images:/openSUSE_13.2/images/openSUSE-13.2-OpenStack-Guest.x86_64-0.0.10-Build2.77.qcow2
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/openSUSE-13.2-OpenStack-Guest.x86_64-0.0.10-Build2.77.qcow2
    openstack image create ${GENERAL_OPTS} --min-disk 11 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=opensuse --property os_version=13 \
        --file openSUSE-13.2-OpenStack-Guest.x86_64-0.0.10-Build2.77.qcow2 opensuse13
fi

if [ ! -e "debian-8.5.0-openstack-amd64.qcow2" ]; then
    #wget --quiet http://cdimage.debian.org/cdimage/openstack/8.5.0/debian-8.5.0-openstack-amd64.qcow2
    wget --quiet http://${LOCALSERVER}/PXEBoot/Images/debian-8.5.0-openstack-amd64.qcow2
    openstack image create ${GENERAL_OPTS} --min-disk 3 \
        --property os_command_line='/usr/sbin/sshd -D' \
        --property os_distro=debian --property os_version=8 \
        --file debian-8.5.0-openstack-amd64.qcow2 jessie
fi
