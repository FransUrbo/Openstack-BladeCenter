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

if [ ! -e "/root/admin-openrc" ]; then
    echo "The /root/admin-openrc file don't exists."
    exit 1
else
    set +x # Disable showing commands this do (password especially).
    . /root/admin-openrc
fi

curl -s http://${LOCALSERVER}/PXEBoot/openstack-configure > \
    /usr/local/bin/openstack-configure
chmod +x /usr/local/bin/openstack-configure

set -xe

# ======================================================================

# Get IP of this host
set -- $(/sbin/ifconfig "eth1" | grep ' inet ')
ip="$(echo "${2}" | sed 's@.*:@@')"

# Get the hostname. This is the simplest and fastest.
hostname="$(cat /etc/hostname)"

# Get some passwords we'll need to modify configuration with.
neutron_pass="$(get_debconf_value "neutron-common" "/mysql/app-pass")"
rabbit_pass="$(get_debconf_value "designate-common" "/rabbit_password")"
admin_pass="$(get_debconf_value "keystone" "keystone/admin-password")"
nova_pass="$(get_debconf_value "nova-common" "/mysql/app-pass")"
nova_api_pass="$(get_debconf_value "nova-api" "/mysql/app-pass")"
magnum_pass="$(get_debconf_value "magnum-common" "/mysql/app-pass")"
email="$(get_debconf_value "keystone" "/admin-email")"
ctrlnode="$(get_debconf_value "keystone" "/remote/host")"

if [ -z "${neutron_pass}" -o -z "${rabbit_pass}" -o -z "${admin_pass}" \
    -o -z "${nova_pass}" -o -z "${nova_api_pass}" -o -z "${magnum_pass}" ]
then
    # Just tripple check.
    echo "Can't get necessary passwords!"
    exit 1
fi

# Setup the bashrc file for Openstack.
cat <<EOF >> /root/.bashrc

# Openstack specials
get_debconf_value () {
    debconf-get-selections | \\
        egrep "^\${1}[ \$(printf '\t')].*\${2}[ \$(printf '\t')]" | \\
        sed 's@.*[ \t]@@'
}

ini_unset_value () {
    local file="\$1"
    local value="\$2"

    sed -i "s@^\(\${value}[ \t]\)=.*@#\1 = <None>@" "\${file}"
}

if [ -f /root/admin-openrc ]; then
    . /root/admin-openrc
else
    echo "WARNING: No /root/admin-openrc."
fi
EOF

exit 0
# ======================================================================

# Configure Designate
cp /etc/designate/designate.conf /etc/designate/designate.conf.orig
openstack-configure set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_userid openstack
openstack-configure set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_password "${rabbit_pass}"
openstack-configure set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_hosts "${ctrlnode}"
openstack-configure set /etc/designate/designate.conf service:central managed_resource_email "${email}"
openstack-configure set /etc/designate/designate.conf network_api:neutron endpoints "europe-london\|http://${ctrlnode}:9696/"
openstack-configure set /etc/designate/designate.conf network_api:neutron admin_username admin
openstack-configure set /etc/designate/designate.conf network_api:neutron admin_password "${neutron_pass}"
openstack-configure set /etc/designate/designate.conf network_api:neutron auth_url "http://${ctrlnode}:35357/v2.0"
openstack-configure set /etc/designate/designate.conf network_api:neutron admin_tenant_name service
openstack-configure set /etc/designate/designate.conf network_api:neutron auth_strategy keystone
openstack-configure set /etc/designate/designate.conf service:api auth_strategy keystone
for init in /etc/init.d/designate-*; do $init restart; done

# Configure Neutron.
cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.orig
openstack-configure set /etc/neutron/neutron.conf DEFAULT default_availability_zones nova
openstack-configure set /etc/neutron/neutron.conf DEFAULT availability_zone nova
openstack-configure set /etc/neutron/neutron.conf DEFAULT core_plugin neutron.plugins.ml2.plugin.Ml2Plugin
openstack-configure set /etc/neutron/neutron.conf keystone_authtoken region_name europe-london
openstack-configure set /etc/neutron/neutron.conf database connection \
    "$(get_debconf_value "openstack" "keystone/password/neutron")"
openstack-configure set /etc/neutron/neutron.conf database use_db_reconnect true

cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.orig
openstack-configure set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver iptables_hybrid
OLD="$(openstack-configure get /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types)"
openstack-configure set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types "${OLD:+${OLD},}vlan"

cp /etc/neutron/neutron_lbaas.conf /etc/neutron/neutron_lbaas.conf.orig
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth auth_url "http://${ctrlnode}:35357/v2.0"
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth admin_username neutron
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth admin_password \
    "$(get_debconf_value "openstack" "keystone/password/neutron")"
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth region europe-london
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth admin_tenant_name service
# TODO: ?? Needs to be done manually ??
#openstack-configure set /etc/neutron/neutron_lbaas.conf DEFAULT interface_driver openvswitch
# TODO: ProgrammingError: (pymysql.err.ProgrammingError) (1146, u"Table 'neutron.lbaas_loadbalancers' doesn't exist")
#OLD="$(openstack-configure get /etc/neutron/neutron.conf DEFAULT service_plugins)"
#openstack-configure set /etc/neutron/neutron.conf DEFAULT service_plugins \
#    "${OLD:+${OLD},}neutron_lbaas.services.loadbalancer.plugin.LoadBalancerPluginv2"
#
#cp /etc/neutron/lbaas_agent.ini /etc/neutron/lbaas_agent.ini.orig
#openstack-configure set /etc/neutron/lbaas_agent.ini DEFAULT device_driver \
#    neutron_lbaas.services.loadbalancer.drivers.haproxy.namespace_driver.HaproxyNSDriver
#openstack-configure set /etc/neutron/lbaas_agent.ini DEFAULT interface_driver \
#    neutron.plugins.services.agent_loadbalancer.plugin.LoadBalancerPluginv2
#
#cp /etc/neutron/neutron_lbaas.conf /etc/neutron/neutron_lbaas.conf.orig
#openstack-configure set /etc/neutron/neutron_lbaas.conf service_providers \
#    "LOADBALANCERV2:Octavia:neutron_lbaas.drivers.octavia.driver.OctaviaDriver:default"

cp /etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini.orig
openstack-configure set /etc/neutron/l3_agent.ini DEFAULT ovs_integration_bridge br-provider
openstack-configure set /etc/neutron/l3_agent.ini DEFAULT external_network_bridge br-physical
openstack-configure set /etc/neutron/l3_agent.ini DEFAULT rpc_workers 5
openstack-configure set /etc/neutron/l3_agent.ini DEFAULT rpc_state_report_workers 5
for init in /etc/init.d/neutron-*; do $init restart; done

# Configure Nova.
cp /etc/nova/nova.conf /etc/nova/nova.conf.orig
openstack-configure set /etc/nova/nova.conf DEFAULT dmz_net 10.99.0.0
openstack-configure set /etc/nova/nova.conf DEFAULT dmz_mask 255.255.255.0
openstack-configure set /etc/nova/nova.conf DEFAULT pybasedir /usr/lib/python2.7/dist-packages
openstack-configure set /etc/nova/nova.conf DEFAULT use_neutron True
openstack-configure set /etc/nova/nova.conf DEFAULT internal_service_availability_zone internal
openstack-configure set /etc/nova/nova.conf DEFAULT default_availability_zone nova
openstack-configure set /etc/nova/nova.conf DEFAULT default_schedule_zone nova
openstack-configure set /etc/nova/nova.conf DEFAULT block_device_allocate_retries 300
openstack-configure set /etc/nova/nova.conf DEFAULT block_device_allocate_retries_interval 10
openstack-configure set /etc/nova/nova.conf DEFAULT block_device_creation_timeout 300
openstack-configure set /etc/nova/nova.conf DEFAULT rpc_backend rabbit
openstack-configure set /etc/nova/nova.conf DEFAULT auth_strategy keystone
openstack-configure set /etc/nova/nova.conf DEFAULT default_flavor m1.nano
openstack-configure set /etc/nova/nova.conf DEFAULT instances_path \$state_path/instances
openstack-configure set /etc/nova/nova.conf DEFAULT resume_guests_state_on_host_boot true
openstack-configure set /etc/nova/nova.conf DEFAULT network_allocate_retries 5
#openstack-configure set /etc/nova/nova.conf DEFAULT max_concurrent_live_migrations 5
openstack-configure set /etc/nova/nova.conf DEFAULT metadata_cache_expiration 60
openstack-configure set /etc/nova/nova.conf DEFAULT remove_unused_base_images false
openstack-configure set /etc/nova/nova.conf DEFAULT cpu_allocation_ratio 8.0
openstack-configure set /etc/nova/nova.conf DEFAULT ram_allocation_ratio 1.0
openstack-configure set /etc/nova/nova.conf DEFAULT disk_allocation_ratio 1.0
openstack-configure set /etc/nova/nova.conf DEFAULT default_ephemeral_format xfs
openstack-configure set /etc/nova/nova.conf DEFAULT public_interface eth1
openstack-configure set /etc/nova/nova.conf DEFAULT console_driver nova.console.xvp.XVPConsoleProxy
openstack-configure set /etc/nova/nova.conf DEFAULT console_public_hostname "${hostname}"
openstack-configure set /etc/nova/nova.conf DEFAULT console_topic console
openstack-configure set /etc/nova/nova.conf database connection "mysql+pymysql://nova:${nova_pass}@${ctrlnode}/nova"
openstack-configure set /etc/nova/nova.conf api_database connection "mysql+pymysql://novaapi:${nova_api_pass}@${ctrlnode}/novaapi"
openstack-configure set /etc/nova/nova.conf cinder cross_az_attach True
openstack-configure set /etc/nova/nova.conf cinder os_region_name europe-london
openstack-configure set /etc/nova/nova.conf cinder admin_username ironic
openstack-configure set /etc/nova/nova.conf cinder admin_password \
    "$(get_debconf_value "openstack" "keystone/password/ironic")"
openstack-configure set /etc/nova/nova.conf cinder admin_tenant_name
#openstack-configure set /etc/nova/nova.conf cinder api_endpoint "http://${ctrlnode}/v2.0"
#openstack-configure set /etc/nova/nova.conf cinder admin_url "http://${ctrlnode}/v2.0"
openstack-configure set /etc/nova/nova.conf keystone_authtoken http_connect_timeout 5
openstack-configure set /etc/nova/nova.conf keystone_authtoken http_request_max_retries 3
openstack-configure set /etc/nova/nova.conf keystone_authtoken region_name europe-london
#openstack-configure set /etc/nova/nova.conf keystone_authtoken auth_uri "http://${ctrlnode}:5000/v3"
#openstack-configure set /etc/nova/nova.conf keystone_authtoken identity_uri "http://${ctrlnode}:35357/v3"
openstack-configure set /etc/nova/nova.conf keystone_authtoken admin_user nova
openstack-configure set /etc/nova/nova.conf keystone_authtoken admin_password \
    "$(get_debconf_value "openstack" "keystone/password/nova")"
openstack-configure set /etc/nova/nova.conf keystone_authtoken admin_tenant_name service
openstack-configure set /etc/nova/nova.conf keystone_authtoken memcached_servers 127.0.0.1:11211
#openstack-configure set /etc/nova/nova.conf neutron url "http://${ctrlnode}:9696/"
#openstack-configure set /etc/nova/nova.conf neutron auth_url "http://${ctrlnode}:5000/v3"
#openstack-configure set /etc/nova/nova.conf neutron auth_type v3password
openstack-configure set /etc/nova/nova.conf neutron username neutron
openstack-configure set /etc/nova/nova.conf neutron password \
    "$(get_debconf_value "openstack" "keystone/password/neutron")"
openstack-configure set /etc/nova/nova.conf neutron project_domain_name default
openstack-configure set /etc/nova/nova.conf neutron project_name service
openstack-configure set /etc/nova/nova.conf neutron tenant_name service
#openstack-configure set /etc/nova/nova.conf neutron user_domain_name default
openstack-configure set /etc/nova/nova.conf neutron ovs_bridge br-provider
openstack-configure set /etc/nova/nova.conf ironic admin_username ironic
openstack-configure set /etc/nova/nova.conf ironic admin_password \
    "$(get_debconf_value "openstack" "keystone/password/ironic")"
openstack-configure set /etc/nova/nova.conf ironic admin_tenant_name service
openstack-configure set /etc/nova/nova.conf ironic api_endpoint "http://${ctrlnode}:6385/v1"
openstack-configure set /etc/nova/nova.conf libvirt disk_cachemodes file=directsync,block=directsync
openstack-configure set /etc/nova/nova.conf glance api_servers "http://${ctrlnode}:9292/"
openstack-configure set /etc/nova/nova.conf glance num_retries 5
#openstack-configure set /etc/nova/nova.conf glance verify_glance_signatures true
openstack-configure set /etc/nova/nova.conf barbican os_region_name europe-london
openstack-configure set /etc/nova/nova.conf vnc enabled true
openstack-configure set /etc/nova/nova.conf vnc vncserver_listen \$my_ip
openstack-configure set /etc/nova/nova.conf vnc vncserver_proxyclient_address \$my_ip
openstack-configure set /etc/nova/nova.conf vnc novncproxy_host \$my_ip
openstack-configure set /etc/nova/nova.conf vnc novncproxy_base_url http://${ip}:6080/vnc_auto.html
openstack-configure set /etc/nova/nova.conf vnc novncproxy_port 6080
openstack-configure set /etc/nova/nova.conf vnc xvpvncproxy_host \$my_ip
openstack-configure set /etc/nova/nova.conf vnc xvpvncproxy_base_url http://${ip}:6081/console
openstack-configure set /etc/nova/nova.conf vnc xvpvncproxy_port 6081
ini_unset_value /etc/nova/nova.conf default_domain_name
ini_unset_value /etc/nova/nova.conf domain_name
for init in /etc/init.d/nova-*; do $init restart; done

# ======================================================================
# Setup Magnum.
cp /etc/magnum/magnum.conf /etc/magnum/magnum.conf.orig
openstack-configure set /etc/magnum/magnum.conf database connection "mysql+pymysql://magnum:${magnum_pass}@${ctrlnode}/magnum"

# ======================================================================
# Setup Open vSwitch
ovs-vsctl del-br br-int
ovs-vsctl add-br br-physical
#ovs-vsctl add-port br-physical eth1 # TODO: !! This will cut traffic on eth1 !!
ovs-vsctl add-br br-provider
ovs-vsctl add-port br-provider eth0

cp /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.orig
openstack-configure set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs bridge_mappings provider:br-provider
openstack-configure set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs local_ip "${ip}"
openstack-configure set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs integration_bridge br-provider
for init in /etc/init.d/*openvswitch*; do $init restart; done

# ======================================================================
# Setup Open iSCSI.
iscsiadm -m iface -I eth1 --op=new
iscsiadm -m iface -I eth1 --op=update -n iface.vlan_priority -v 1
