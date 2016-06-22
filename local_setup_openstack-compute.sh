#!/bin/sh

get_debconf_value () {
    debconf-get-selections | \
        egrep "^${1}[ $(printf '\t')].*${2}[ $(printf '\t')]" | \
        sed 's@.*[ \t]@@'
}

ini_unset_value () {
    local file="$1"
    local value="$2"

    sed -i "s@^\(${value}[ \t]\)=.*@#\1 = <None>@" "${file}"
}

if [ ! -e /usr/share/openstack-pkg-tools/pkgos_func ]; then
    echo "ERROR: openstack-pkg-tools not installed"
    exit 1
else
    . /usr/share/openstack-pkg-tools/pkgos_func
    export PKGOS_VERBOSE=yes
fi

if [ ! -e "/root/admin-openrc" ]; then
    echo "The /root/admin-openrc file don't exists."
    exit 1
else
    set +x # Disable showing commands this do (password especially).
    . /root/admin-openrc
fi

set -xe

# ======================================================================

# Get IP of this host
set -- $(/sbin/ip address | egrep " eth.* UP ")
iface="$(echo "${2}" | sed 's@:@@')"
set -- $(/sbin/ifconfig "${iface}" | grep ' inet ')
ip="$(echo "${2}" | sed 's@.*:@@')"

# Get the hostname. This is the simplest and fastest.
hostname="$(cat /etc/hostname)"

admin_pass="$(get_debconf_value "keystone" "keystone/admin-password")"
neutron_pass="$(get_debconf_value "neutron-common" "/mysql/app-pass")"
rabbit_pass="$(get_debconf_value "designate-common" "/rabbit_password")"
nova_pass="$(get_debconf_value "nova-common" "/mysql/app-pass")"
nova_api_pass="$(get_debconf_value "nova-api" "/mysql/app-pass")"
magnum_pass="$(get_debconf_value "magnum-common" "/mysql/app-pass")"
email="$(get_debconf_value "keystone" "/admin-email")"
ctrlnode="$(get_debconf_value "keystone" "/remote/host")"

if [ -z "${neutron_pass}" -o -z "${rabbit_pass}" -o -z "${nova_pass}" \
     -o -z "${nova_api_pass}" -o -z "${magnum_pass}" ]
then
    curl -s http://${LOCALSERVER}/PXEBoot/debconf_openstack-compute.txt | \
        sed "s@10\.0\.4\.1@${ip}@" | \
        debconf-set-selections
    neutron_pass="$(get_debconf_value "neutron-common" "/mysql/app-pass")"
    rabbit_pass="$(get_debconf_value "designate-common" "/rabbit_password")"
    nova_pass="$(get_debconf_value "nova-common" "/mysql/app-pass")"
    nova_api_pass="$(get_debconf_value "nova-api" "/mysql/app-pass")"
    magnum_pass="$(get_debconf_value "magnum-common" "/mysql/app-pass")"
    if [ -z "${neutron_pass}" -o -z "${rabbit_pass}" -o -z "${nova_pass}" \
         -o -z "${nova_api_pass}" -o -z "${magnum_pass}" ]
    then
        echo "Can't get necessary passwords"
        exit 1
    fi
fi

# Setup the bashrc file for Openstack.
cat <<EOF >> /root/.bashrc

# Openstack specials
[ -f /root/admin-openrc ] && . /root/admin-openrc
[ -f /usr/share/openstack-pkg-tools/pkgos_func ] && \\
    . /usr/share/openstack-pkg-tools/pkgos_func
export PKGOS_VERBOSE=yes
EOF

# ======================================================================

# Configure Designate
cp /etc/designate/designate.conf /etc/designate/designate.conf.orig
pkgos_inifile set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_userid openstack
pkgos_inifile set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_password "${rabbit_pass}"
pkgos_inifile set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_hosts "${ctrlnode}"
pkgos_inifile set /etc/designate/designate.conf service:central managed_resource_email "${email}"
pkgos_inifile set /etc/designate/designate.conf network_api:neutron endpoints "europe-london\|http://${ctrlnode}:9696/"
#pkgos_inifile set /etc/designate/designate.conf network_api:neutron admin_username admin
#pkgos_inifile set /etc/designate/designate.conf network_api:neutron admin_password "${neutron_pass}"
#pkgos_inifile set /etc/designate/designate.conf network_api:neutron auth_url "http://${ctrlnode}:35357/v2.0"
pkgos_inifile set /etc/designate/designate.conf network_api:neutron auth_strategy keystone
pkgos_inifile set /etc/designate/designate.conf service:api auth_strategy keystone
for init in /etc/init.d/designate-*; do $init restart; done

# Configure Neutron.
cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.orig
pkgos_inifile set /etc/neutron/neutron.conf DEFAULT default_availability_zones nova
pkgos_inifile set /etc/neutron/neutron.conf DEFAULT availability_zone nova
pkgos_inifile set /etc/neutron/neutron.conf keystone_authtoken region_name europe-london

cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.orig
pkgos_inifile set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver iptables_hybrid

cp /etc/neutron/neutron_lbaas.conf /etc/neutron/neutron_lbaas.conf.orig
#pkgos_inifile set /etc/neutron/neutron_lbaas.conf service_auth auth_url "http://${ctrlnode}:35357/v2.0"
#pkgos_inifile set /etc/neutron/neutron_lbaas.conf service_auth admin_username ???
#pkgos_inifile set /etc/neutron/neutron_lbaas.conf service_auth admin_password \
#    "$(get_debconf_value "openstack" "keystone/password/???")"
pkgos_inifile set /etc/neutron/neutron_lbaas.conf service_auth region europe-london
#pkgos_inifile set /etc/neutron/neutron_lbaas.conf DEFAULT interface_driver openvswitch # Needs to be done manually
pkgos_inifile get /etc/neutron/neutron.conf DEFAULT service_plugins
#
#lbaas									=> not found
#lbaasv2								=> not found
#neutron.lbaas.loadbalancer.LoadBalancer				=> not found
#neutron.lbaas.loadbalancer:LoadBalancer				=> not found
#neutron.lbaas.services.loadbalancer.plugin.LoadBalancer		=> not found
#neutron.lbaas.services.loadbalancer.plugin:LoadBalancer		=> not found
#neutron.services.loadbalancer.plugin.LoadBalancerPlugin                => not found
#neutron.services.loadbalancer.plugin:LoadBalancerPlugin                => not found
#neutron.services.loadbalancer.plugin.LoadBalancerPluginv2		=> not found
#neutron.services.loadbalancer.plugin:LoadBalancerPluginv2		=> not found
#neutron_lbaas.services.loadbalancer.plugin.LoadBalancerPlugin		=> not found
#neutron_lbaas.services.loadbalancer.plugin:LoadBalancerPlugin		=> not found
#neutron_lbaas.services.loadbalancer.plugin.LoadBalancerPluginv2        => not found
#neutron_lbaas.services.loadbalancer.plugin:LoadBalancerPluginv2        => not found
#if [ "${RET}" != "NO_VALUE" ]; then
#    [ -n "${RET}" ] && RET="${RET},"
#    pkgos_inifile set /etc/neutron/neutron.conf DEFAULT service_plugins "${RET}???"
#fi
for init in /etc/init.d/neutron-*; do $init restart; done

# Configure Nova.
cp /etc/nova/nova.conf /etc/nova/nova.conf.orig
pkgos_inifile set /etc/nova/nova.conf DEFAULT dmz_net 10.99.0.0
pkgos_inifile set /etc/nova/nova.conf DEFAULT dmz_mask 255.255.255.0
pkgos_inifile set /etc/nova/nova.conf DEFAULT pybasedir /usr/lib/python2.7/dist-packages
pkgos_inifile set /etc/nova/nova.conf DEFAULT use_neutron True
pkgos_inifile set /etc/nova/nova.conf DEFAULT internal_service_availability_zone internal
pkgos_inifile set /etc/nova/nova.conf DEFAULT default_availability_zone nova
pkgos_inifile set /etc/nova/nova.conf DEFAULT default_schedule_zone nova
pkgos_inifile set /etc/nova/nova.conf DEFAULT block_device_allocate_retries 300
pkgos_inifile set /etc/nova/nova.conf DEFAULT block_device_allocate_retries_interval 10
pkgos_inifile set /etc/nova/nova.conf DEFAULT block_device_creation_timeout 300
pkgos_inifile set /etc/nova/nova.conf DEFAULT rpc_backend rabbit
pkgos_inifile set /etc/nova/nova.conf DEFAULT auth_strategy keystone
pkgos_inifile set /etc/nova/nova.conf database connection "mysql+pymysql://nova:${nova_pass}@${ctrlnode}/nova"
pkgos_inifile set /etc/nova/nova.conf api_database connection "mysql+pymysql://novaapi:${nova_api_pass}@${ctrlnode}/novaapi"
pkgos_inifile set /etc/nova/nova.conf cinder cross_az_attach True
pkgos_inifile set /etc/nova/nova.conf cinder os_region_name europe-london
pkgos_inifile set /etc/nova/nova.conf cinder admin_username ironic
pkgos_inifile set /etc/nova/nova.conf cinder admin_password \
    "$(get_debconf_value "openstack" "keystone/password/ironic")"
pkgos_inifile set /etc/nova/nova.conf cinder admin_tenant_name
#pkgos_inifile set /etc/nova/nova.conf cinder api_endpoint "http://${ctrlnode}/v2.0"
#pkgos_inifile set /etc/nova/nova.conf cinder admin_url "http://${ctrlnode}/v2.0"
pkgos_inifile set /etc/nova/nova.conf keystone_authtoken http_connect_timeout 5
pkgos_inifile set /etc/nova/nova.conf keystone_authtoken http_request_max_retries 3
pkgos_inifile set /etc/nova/nova.conf keystone_authtoken region_name europe-london
#pkgos_inifile set /etc/nova/nova.conf keystone_authtoken auth_uri "http://${ctrlnode}:5000/v3"
#pkgos_inifile set /etc/nova/nova.conf keystone_authtoken identity_uri "http://${ctrlnode}:35357/v3"
pkgos_inifile set /etc/nova/nova.conf keystone_authtoken admin_user nova
pkgos_inifile set /etc/nova/nova.conf keystone_authtoken admin_password \
    "$(get_debconf_value "openstack" "keystone/password/nova")"
pkgos_inifile set /etc/nova/nova.conf keystone_authtoken admin_tenant_name service
pkgos_inifile set /etc/nova/nova.conf keystone_authtoken memcached_servers 127.0.0.1:11211
#pkgos_inifile set /etc/nova/nova.conf neutron url "http://${ctrlnode}:9696/"
#pkgos_inifile set /etc/nova/nova.conf neutron auth_url "http://${ctrlnode}:5000/v3"
#pkgos_inifile set /etc/nova/nova.conf neutron auth_type v3password
pkgos_inifile set /etc/nova/nova.conf neutron username neutron
pkgos_inifile set /etc/nova/nova.conf neutron password \
    "$(get_debconf_value "openstack" "keystone/password/neutron")"
pkgos_inifile set /etc/nova/nova.conf neutron project_domain_name default
pkgos_inifile set /etc/nova/nova.conf neutron project_name service
pkgos_inifile set /etc/nova/nova.conf neutron tenant_name service
pkgos_inifile set /etc/nova/nova.conf neutron user_domain_name default
pkgos_inifile set /etc/nova/nova.conf neutron ovs_bridge br-provider
pkgos_inifile set /etc/nova/nova.conf ironic admin_username ironic
pkgos_inifile set /etc/nova/nova.conf ironic admin_password \
    "$(get_debconf_value "openstack" "keystone/password/ironic")"
pkgos_inifile set /etc/nova/nova.conf ironic admin_tenant_name service
for init in /etc/init.d/nova-*; do $init restart; done

# ======================================================================
# Setup Magnum.
cp /etc/magnum/magnum.conf /etc/magnum/magnum.conf.orig
pkgos_inifile set /etc/magnum/magnum.conf database connection "mysql+pymysql://magnum:${magnum_pass}@${ctrlnode}/magnum"

# ======================================================================
# Setup Open vSwitch
ovs-vsctl del-br br-int                                                                                                                                      |
ovs-vsctl add-br br-physical
#ovs-vsctl add-port br-physical eth1 # TODO: !! This will cut traffic on eth1 !!
ovs-vsctl add-br br-provider
ovs-vsctl add-port br-provider eth0

cp /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.orig
pkgos_inifile set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs bridge_mappings provider:br-provider
pkgos_inifile set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs local_ip "${ip}"
for init in /etc/init.d/*openvswitch*; do $init restart; done
