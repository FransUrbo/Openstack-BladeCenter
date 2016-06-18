#!/bin/sh

set -x

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

neutron_pass="$(get_debconf_value "neutron-common" "/mysql/app-pass")"
rabbit_pass="$(get_debconf_value "designate-common" "/rabbit_password")"
email="$(get_debconf_value "keystone" "/admin-email")"
ctrlnode="$(get_debconf_value "keystone" "remote/host")"

if [ -z "${neutron_pass}" -o -z "${rabbit_pass}" ]; then
    curl -s http://${LOCALSERVER}/PXEBoot/debconf_openstack-compute.txt | \
        sed "s@10\.0\.4\.1@${ip}@" | \
        debconf-set-selections
    neutron_pass="$(get_debconf_value "neutron-common" "/mysql/app-pass")"
    rabbit_pass="$(get_debconf_value "designate-common" "/rabbit_password")"
fi

# Setup the bashrc file for Openstack.
cat <<EOF >> /root/.bashrc

# Openstack specials
. /root/admin-openrc
. /usr/share/openstack-pkg-tools/pkgos_func
export PKGOS_VERBOSE=yes
EOF

# ======================================================================

# Configure Designate
pkgos_inifile set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_userid openstack
pkgos_inifile set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_password "${rabbit_pass}"
pkgos_inifile set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_hosts "${ctrlnode}"
pkgos_inifile set /etc/designate/designate.conf service:central managed_resource_email "${email}"
pkgos_inifile set /etc/designate/designate.conf pool_manager_cache:memcache memcached_servers 127.0.0.1:11211
pkgos_inifile set /etc/designate/designate.conf network_api:neutron endpoints "europe-london\|http://${ctrlnode}:9696/"
pkgos_inifile set /etc/designate/designate.conf network_api:neutron admin_username admin
pkgos_inifile set /etc/designate/designate.conf network_api:neutron admin_password "${neutron_pass}"
pkgos_inifile set /etc/designate/designate.conf network_api:neutron auth_url "http://${ctrlnode}:35357/v2.0"
pkgos_inifile set /etc/designate/designate.conf network_api:neutron auth_strategy keystone
for init in /etc/init.d/designate-*; do $init restart; done

# Configure Neutron.
pkgos_inifile set /etc/neutron/neutron.conf DEFAULT default_availability_zones nova
pkgos_inifile set /etc/neutron/neutron.conf DEFAULT availability_zone nova
pkgos_inifile set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver iptables_hybrid
pkgos_inifile set /etc/neutron/neutron_lbaas.conf service_auth auth_url "http://${ctrlnode}:35357/v2.0"
pkgos_inifile set /etc/neutron/neutron_lbaas.conf service_auth admin_username admi
pkgos_inifile set /etc/neutron/neutron_lbaas.conf service_auth admin_password "${neutron_pass}"
pkgos_inifile set /etc/neutron/neutron_lbaas.conf service_auth region europe-london
#pkgos_inifile set /etc/neutron/neutron_lbaas.conf DEFAULT interface_driver openvswitch # Needs to be done manually
pkgos_inifile get /etc/neutron/neutron.conf DEFAULT service_plugins
#if [ "${RET}" != "NO_VALUE" ]; then
#    [ -n "${RET}" ] && RET="${RET},"
#    pkgos_inifile set /etc/neutron/neutron.conf DEFAULT service_plugins "${RET}???"
#fi
for init in /etc/init.d/neutron-*; do $init restart; done

# Configure Nova.
pkgos_inifile set /etc/nova/nova.conf DEFAULT dmz_net 10.99.0.0
pkgos_inifile set /etc/nova/nova.conf DEFAULT dmz_mask 255.255.255.0
#pkgos_inifile set /etc/nova/nova.conf DEFAULT pybasedir /usr/lib/python2.7/dist-packages,/usr/local/lib/python2.7/dist-packages
pkgos_inifile set /etc/nova/nova.conf DEFAULT pybasedir /usr/lib/python2.7/dist-packages
pkgos_inifile set /etc/nova/nova.conf DEFAULT memcached_servers 127.0.0.1:11211
pkgos_inifile set /etc/nova/nova.conf DEFAULT internal_service_availability_zone internal
pkgos_inifile set /etc/nova/nova.conf DEFAULT default_availability_zone nova
pkgos_inifile set /etc/nova/nova.conf DEFAULT default_schedule_zone nova
pkgos_inifile set /etc/nova/nova.conf DEFAULT block_device_allocate_retries 300
pkgos_inifile set /etc/nova/nova.conf DEFAULT block_device_allocate_retries_interval 10
pkgos_inifile set /etc/nova/nova.conf DEFAULT block_device_creation_timeout 300
pkgos_inifile set /etc/nova/nova.conf cinder cross_az_attach True
pkgos_inifile set /etc/nova/nova.conf cinder os_region_name europe-london
for init in /etc/init.d/nova-*; do $init restart; done

# ======================================================================
# Setup Open vSwitch
ovs-vsctl add-br br-physical
#ovs-vsctl add-port br-physical eth1 # TODO: !! This will cut traffic on eth1 !!
ovs-vsctl add-br br-provider
ovs-vsctl add-port br-provider eth0
pkgos_inifile set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs bridge_mappings provider:br-provider
pkgos_inifile set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs local_ip "${ip}"
for init in /etc/init.d/*openvswitch*; do $init restart; done
