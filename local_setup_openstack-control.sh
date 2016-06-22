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
set -- $(/sbin/ip address | egrep " eth.* UP ")
iface="$(echo "${2}" | sed 's@:@@')"
set -- $(/sbin/ifconfig "${iface}" | grep ' inet ')
ip="$(echo "${2}" | sed 's@.*:@@')"

# Get the hostname. This is the simplest and fastest.
hostname="$(cat /etc/hostname)"

# Get some passwords we'll need to modify configuration with.
neutron_pass="$(get_debconf_value "neutron-common" "/mysql/app-pass")"
rabbit_pass="$(get_debconf_value "designate-common" "/rabbit_password")"
admin_pass="$(get_debconf_value "keystone" "/admin-password")"
aodh_pass="$(get_debconf_value "aodh-common" "/mysql/app-pass")"
mongo_ceilodb_pass="$(get_debconf_value "openstack" "/db_password")"
email="$(get_debconf_value "keystone" "/admin-email")"
ctrlnode="$(get_debconf_value "keystone" "/remote/host")"

if [ -z "${neutron_pass}" -o -z "${rabbit_pass}" -o -z "${admin_pass}" \
    -o -z "${aodh_pass}" -o -z "${mongo_ceilodb_pass}" -o -z "${ctrlnode}" ]
then
    # Just tripple check.
    echo "Can't get necessary passwords!"
    exit 1
fi

# Setup the bashrc file for Openstack.
cat <<EOF >> /root/.bashrc

# Openstack specials
do_install() {
    apt-get -y --no-install-recommends install \$*
}

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

[ -f /root/admin-openrc ] && . /root/admin-openrc
EOF

# ======================================================================

# Configure Keystone.
cp /etc/keystone/keystone.conf /etc/keystone/keystone.conf.orig
openstack-configure set /etc/keystone/keystone.conf database use_db_reconnect true
openstack-configure set /etc/keystone/keystone.conf database db_retry_interval 1
openstack-configure set /etc/keystone/keystone.conf database db_inc_retry_interval true
openstack-configure set /etc/keystone/keystone.conf database db_max_retry_interval 10
openstack-configure set /etc/keystone/keystone.conf database db_max_retries 20
openstack-configure set /etc/keystone/keystone.conf oslo_messaging_rabbit rabbit_host "${ctrlnode}"
openstack-configure set /etc/keystone/keystone.conf oslo_messaging_rabbit rabbit_userid openstack
openstack-configure set /etc/keystone/keystone.conf oslo_messaging_rabbit rabbit_password "${rabbit_pass}"
#openstack-configure set /etc/keystone/keystone.conf ldap url ldap://server.domain.tld
#openstack-configure set /etc/keystone/keystone.conf ldap suffix c=SE
#openstack-configure set /etc/keystone/keystone.conf ldap use_dumb_member true
#openstack-configure set /etc/keystone/keystone.conf ldap dumb_member cn=dumb,dc=nonexistent
#openstack-configure set /etc/keystone/keystone.conf ldap query_scope sub
#openstack-configure set /etc/keystone/keystone.conf ldap user_filter uid=%
#openstack-configure set /etc/keystone/keystone.conf ldap user_objectclass person
#openstack-configure set /etc/keystone/keystone.conf ldap user_id_attribute uid
#openstack-configure set /etc/keystone/keystone.conf ldap user_name_attribute cn
#openstack-configure set /etc/keystone/keystone.conf ldap user_mail_attribute mail
#openstack-configure set /etc/keystone/keystone.conf ldap user_pass_attribute userPassword
#TODO: [...]
#http://docs.openstack.org/admin-guide/keystone_integrate_with_ldap.html
#ini_unset_value /etc/keystone/keystone.conf admin_token # TODO: ?? Nothing works without this ??

# Configure Designate.
cp /etc/designate/designate.conf /etc/designate/designate.conf.orig
openstack-configure set /etc/designate/designate.conf DEFAULT auth_strategy keystone
openstack-configure set /etc/designate/designate.conf service:api auth_strategy keystone
openstack-configure set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_userid openstack
openstack-configure set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_password "${rabbit_pass}"
openstack-configure set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_hosts "${ctrlnode}"
openstack-configure set /etc/designate/designate.conf service:central managed_resource_email "${email}"
openstack-configure set /etc/designate/designate.conf pool_manager_cache:memcache memcached_servers 127.0.0.1:11211
openstack-configure set /etc/designate/designate.conf network_api:neutron endpoints "europe-london\|http://${ctrlnode}:9696/"
openstack-configure set /etc/designate/designate.conf network_api:neutron admin_username admin
openstack-configure set /etc/designate/designate.conf network_api:neutron admin_password "${neutron_pass}"
openstack-configure set /etc/designate/designate.conf network_api:neutron auth_url "http://${ctrlnode}:35357/v2.0"
openstack-configure set /etc/designate/designate.conf network_api:neutron admin_tenant_name service
openstack-configure set /etc/designate/designate.conf network_api:neutron auth_strategy keystone

# Configure Manila.
cp /etc/manila/manila.conf /etc/manila/manila.conf.orig
openstack-configure set /etc/manila/manila.conf DEFAULT driver_handles_share_servers True
openstack-configure set /etc/manila/manila.conf DEFAULT service_instance_user True
openstack-configure set /etc/manila/manila.conf DEFAULT storage_availability_zone nova
openstack-configure set /etc/manila/manila.conf DEFAULT rpc_backend rabbit
openstack-configure set /etc/manila/manila.conf DEFAULT default_share_type default_share_type
openstack-configure set /etc/manila/manila.conf DEFAULT rootwrap_config /etc/manila/rootwrap.conf
openstack-configure set /etc/manila/manila.conf DEFAULT auth_strategy keystone
openstack-configure set /etc/manila/manila.conf DEFAULT memcached_servers 127.0.0.1:11211
openstack-configure set /etc/manila/manila.conf DEFAULT my_ip "${ip}"
openstack-configure set /etc/manila/manila.conf DEFAULT enabled_share_backends lvm
openstack-configure set /etc/manila/manila.conf DEFAULT enabled_share_protocols NFS,CIFS
cat <<EOF >> /etc/manila/manila.conf

[lvm]
share_backend_name = LVM
share_driver = manila.share.drivers.lvm.LVMShareDriver
driver_handles_share_servers = False
lvm_share_volume_group = blade_center
lvm_share_export_ip = 10.0.4.1
EOF

# Configure Nova.
cp /etc/nova/nova.conf /etc/nova/nova.conf.orig
openstack-configure set /etc/nova/nova.conf DEFAULT auth_strategy keystone
openstack-configure set /etc/nova/nova.conf DEFAULT dmz_net 10.99.0.0
openstack-configure set /etc/nova/nova.conf DEFAULT dmz_mask 255.255.255.0
openstack-configure set /etc/nova/nova.conf DEFAULT pybasedir /usr/lib/python2.7/dist-packages
openstack-configure set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
openstack-configure set /etc/nova/nova.conf DEFAULT use_neutron True
openstack-configure set /etc/nova/nova.conf DEFAULT memcached_servers 127.0.0.1:11211
openstack-configure set /etc/nova/nova.conf DEFAULT internal_service_availability_zone internal
openstack-configure set /etc/nova/nova.conf DEFAULT default_availability_zone nova
openstack-configure set /etc/nova/nova.conf DEFAULT default_schedule_zone nova
openstack-configure set /etc/nova/nova.conf DEFAULT block_device_allocate_retries 300
openstack-configure set /etc/nova/nova.conf DEFAULT block_device_allocate_retries_interval 10
openstack-configure set /etc/nova/nova.conf DEFAULT block_device_creation_timeout 300
openstack-configure set /etc/nova/nova.conf DEFAULT scheduler_default_filters RetryFilter,AvailabilityZoneFilter,RamFilter,DiskFilter,ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ServerGroupAntiAffinityFilter,ServerGroupAffinityFilter
openstack-configure set /etc/nova/nova.conf DEFAULT baremetal_scheduler_default_filters RetryFilter,AvailabilityZoneFilter,ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ExactRamFilter,ExactDiskFilter,ExactCoreFilter
openstack-configure set /etc/nova/nova.conf DEFAULT my_block_storage_ip \$my_ip
openstack-configure set /etc/nova/nova.conf DEFAULT routing_source_ip \$my_ip
openstack-configure set /etc/nova/nova.conf DEFAULT metadata_host \$my_ip
openstack-configure set /etc/nova/nova.conf DEFAULT instance_usage_audit True
openstack-configure set /etc/nova/nova.conf DEFAULT instance_usage_audit_period Hour
openstack-configure set /etc/nova/nova.conf DEFAULT notify_on_state_change vm_and_task_state
openstack-configure set /etc/nova/nova.conf DEFAULT driver messagingv2
openstack-configure set /etc/nova/nova.conf DEFAULT rpc_backend rabbit
openstack-configure set /etc/nova/nova.conf cinder cross_az_attach True
openstack-configure set /etc/nova/nova.conf keystone_authtoken http_connect_timeout 5
openstack-configure set /etc/nova/nova.conf keystone_authtoken http_request_max_retries 3
openstack-configure set /etc/nova/nova.conf keystone_authtoken region_name europe-london
openstack-configure set /etc/nova/nova.conf neutron region_name europe-london
openstack-configure set /etc/nova/nova.conf neutron domain_name default
openstack-configure set /etc/nova/nova.conf neutron default_domain_name default
openstack-configure set /etc/nova/nova.conf neutron project_domain_name default
openstack-configure set /etc/nova/nova.conf keystone_authtoken auth_uri "http://${ctrlnode}:5000/v3"
openstack-configure set /etc/nova/nova.conf keystone_authtoken auth_version 3
openstack-configure set /etc/nova/nova.conf keystone_authtoken identity_uri "http://${ctrlnode}:35357/v3"
openstack-configure set /etc/nova/nova.conf ironic admin_tenant_name service
ini_unset_value /etc/nova/nova.conf user_domain_id
ini_unset_value /etc/nova/nova.conf user_domain_name
ini_unset_value /etc/nova/nova.conf auth_host
ini_unset_value /etc/nova/nova.conf auth_protocol

cp /etc/nova/nova-compute.conf /etc/nova/nova-compute.conf.orig
openstack-configure set /etc/nova/nova-compute.conf DEFAULT neutron_ovs_bridge br-physical

# Configure Zaqar.
cp /etc/zaqar/zaqar.conf /etc/zaqar/zaqar.conf.orig
openstack-configure set /etc/zaqar/zaqar.conf DEFAULT unreliable True
openstack-configure set /etc/zaqar/zaqar.conf DEFAULT auth_strategy keystone
openstack-configure set /etc/zaqar/zaqar.conf "drivers:management_store:mongodb" database zaqar
openstack-configure set /etc/zaqar/zaqar.conf keystone_authtoken memcached_servers 127.0.0.1:11211
openstack-configure set /etc/zaqar/zaqar.conf drivers:transport:wsgi bind "${ip}"

# Configure Cinder.
cp /etc/cinder/cinder.conf /etc/cinder/cinder.conf.orig
openstack-configure set /etc/cinder/cinder.conf DEFAULT my_ip "${ip}"
openstack-configure set /etc/cinder/cinder.conf DEFAULT volume_group blade_center
openstack-configure set /etc/cinder/cinder.conf DEFAULT storage_availability_zone nova
openstack-configure set /etc/cinder/cinder.conf DEFAULT default_availability_zone nova
openstack-configure set /etc/cinder/cinder.conf DEFAULT scheduler_driver cinder.scheduler.filter_scheduler.FilterScheduler
# TODO: !! Not yet - as soon as we get Cinder-ZoL plugin to work. !!
#openstack-configure set /etc/cinder/cinder.conf DEFAULT nas_ip 192.168.69.8
#openstack-configure set /etc/cinder/cinder.conf DEFAULT nas_login root
#openstack-configure set /etc/cinder/cinder.conf DEFAULT nas_private_key /etc/cinder/sshkey
#openstack-configure set /etc/cinder/cinder.conf DEFAULT nas_share_path share/Blade_Center
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_target_prefix iqn.2010-10.org.openstack:
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_port 3260
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_iotype blockio
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_write_cache on
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_ip_address \$my_ip
openstack-configure set /etc/cinder/cinder.conf DEFAULT volume_name_template '%s'
openstack-configure set /etc/cinder/cinder.conf DEFAULT snapshot_name_template '%s.snap'
openstack-configure set /etc/cinder/cinder.conf DEFAULT backup_name_template '%s.back'
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_helper tgtadm
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_protocol iscsi
openstack-configure set /etc/cinder/cinder.conf DEFAULT volume_dd_blocksize 4M
openstack-configure set /etc/cinder/cinder.conf DEFAULT rpc_backend rabbit
openstack-configure set /etc/cinder/cinder.conf DEFAULT auth_strategy keystone
openstack-configure set /etc/cinder/cinder.conf DEFAULT glance_api_servers "http://${ctrlnode}:9292/"
OLD="$(openstack-configure get /etc/cinder/cinder.conf DEFAULT enabled_backends)"
[ -n "${OLD}" ] && OLD="${OLD},"
openstack-configure set /etc/cinder/cinder.conf DEFAULT enabled_backends "${OLD}nfs"
set -i "s@^\(volume_driver[ \t].*\)@#\1@" /etc/cinder/cinder.conf
openstack-configure set /etc/cinder/cinder.conf DEFAULT nfs_shares_config /etc/cinder/nfs.conf
openstack-configure set /etc/cinder/cinder.conf DEFAULT nfs_sparsed_volumes true
openstack-configure set /etc/cinder/cinder.conf DEFAULT enable_v1_api false
openstack-configure set /etc/cinder/cinder.conf DEFAULT enable_v3_api true

openstack-configure set /etc/cinder/cinder.conf oslo_messaging_notifications driver messagingv2
openstack-configure set /etc/cinder/cinder.conf keystone_authtoken memcached_servers 127.0.0.1:11211
openstack-configure set /etc/cinder/cinder.conf lvm volume_group blade_center
#TODO: ?? Enable this ??
#echo "*/5 * * * *	/usr/bin/cinder-volume-usage-audit --send_actions" > \
#    /etc/cron.d/cinder-volume-usage-audit

# Configure Glance.
cp /etc/glance/glance-api.conf /etc/glance/glance-api.conf.orig
openstack-configure set /etc/glance/glance-api.conf DEFAULT rpc_backend rabbit
openstack-configure set /etc/glance/glance-api.conf oslo_messaging_notifications driver messagingv2
openstack-configure set /etc/glance/glance-api.conf keystone_authtoken memcached_servers 127.0.0.1:11211

# Configure Ceilometer.
cp /etc/ceilometer/ceilometer.conf /etc/ceilometer/ceilometer.conf.orig
openstack-configure set /etc/ceilometer/ceilometer.conf DEFAULT rpc_backend rabbit
openstack-configure set /etc/ceilometer/ceilometer.conf keystone_authtoken memcached_servers 127.0.0.1:11211
openstack-configure set /etc/ceilometer/ceilometer.conf database connection "mongodb://ceilometer:${mongo_ceilodb_pass}@${ctrlnode}:27017/ceilometer"

# Configure Aodh.
cp /etc/aodh/aodh.conf /etc/aodh/aodh.conf.orig
openstack-configure set /etc/aodh/aodh.conf DEFAULT rpc_backend rabbit
openstack-configure set /etc/aodh/aodh.conf oslo_messaging_rabbit rabbit_host "${ctrlnode}"
openstack-configure set /etc/aodh/aodh.conf oslo_messaging_rabbit rabbit_userid openstack
openstack-configure set /etc/aodh/aodh.conf oslo_messaging_rabbit rabbit_password "${rabbit_pass}"
openstack-configure set /etc/aodh/aodh.conf database connection "mysql+pymysql://aodh:${aodh_pass}@${ctrlnode}/aodh"
openstack-configure set /etc/aodh/aodh.conf keystone_authtoken memcached_servers 127.0.0.1:11211
#openstack-configure set /etc/aodh/aodh.conf keystone_authtoken admin_password "${admin_pass}"

# Configure Neutron.
cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.orig
openstack-configure set /etc/neutron/neutron.conf DEFAULT bind_host 0.0.0.0
openstack-configure set /etc/neutron/neutron.conf DEFAULT default_availability_zones nova
openstack-configure set /etc/neutron/neutron.conf DEFAULT availability_zone nova
# neutron.plugins.openvswitch.ovs_neutron_plugin.OVSNeutronPluginV2                    NEUTRON_PLUGIN_NAME=OpenVSwitch
# neutron.plugins.linuxbridge.lb_neutron_plugin.LinuxBridgePluginV2                    NEUTRON_PLUGIN_NAME=LinuxBridge
# neutron.plugins.ml2.plugin.Ml2Plugin                                                 NEUTRON_PLUGIN_NAME=ml2
# neutron.plugins.ryu.ryu_neutron_plugin.RyuNeutronPluginV2                            NEUTRON_PLUGIN_NAME=RYU
# neutron.plugins.plumgrid.plumgrid_nos_plugin.plumgrid_plugin.NeutronPluginPLUMgridV2 NEUTRON_PLUGIN_NAME=PLUMgrid
# neutron.plugins.brocade.NeutronPlugin.BrocadePluginV2                                NEUTRON_PLUGIN_NAME=Brocade
# neutron.plugins.hyperv.hyperv_neutron_plugin.HyperVNeutronPlugin                     NEUTRON_PLUGIN_NAME=Hyper-V
# neutron.plugins.bigswitch.plugin.NeutronRestProxyV2                                  NEUTRON_PLUGIN_NAME=BigSwitch
# neutron.plugins.cisco.network_plugin.PluginV2                                        NEUTRON_PLUGIN_NAME=Cisco
# neutron.plugins.nicira.NeutronPlugin.NvpPluginV2                                     NEUTRON_PLUGIN_NAME=neutron.plugins.nicira.NeutronPlugin.NvpPluginV2
# neutron.plugins.midonet.plugin.MidonetPluginV2                                       NEUTRON_PLUGIN_NAME=Midonet
# neutron.plugins.nec.nec_plugin.NECPluginV2                                           NEUTRON_PLUGIN_NAME=Nec
# neutron.plugins.metaplugin.meta_neutron_plugin.MetaPluginV2                          NEUTRON_PLUGIN_NAME=MetaPlugin
# neutron.plugins.mlnx.mlnx_plugin.MellanoxEswitchPlugin                               NEUTRON_PLUGIN_NAME=Mellanox
# TODO: !! ERROR neutron ImportError: Plugin 'neutron.plugins.openvswitch.ovs_neutron_plugin.OVSNeutronPluginV2' not found !!
#openstack-configure set /etc/neutron/neutron.conf DEFAULT core_plugin neutron.plugins.openvswitch.ovs_neutron_plugin.OVSNeutronPluginV2
openstack-configure set /etc/neutron/neutron.conf DEFAULT core_plugin neutron.plugins.ml2.plugin.Ml2Plugin
openstack-configure set /etc/neutron/neutron.conf keystone_authtoken region_name europe-london
openstack-configure set /etc/neutron/neutron.conf keystone_authtoken http_connect_timeout 5
openstack-configure set /etc/neutron/neutron.conf keystone_authtoken http_request_max_retries 3
openstack-configure set /etc/neutron/neutron.conf keystone_authtoken region_name europe-london
# TODO: ??
#openstack-configure set /etc/neutron/neutron.conf keystone_authtoken auth_uri "http://${ctrlnode}:5000/v3"
#openstack-configure set /etc/neutron/neutron.conf keystone_authtoken identity_uri "http://${ctrlnode}:35357/v3"
#ini_unset_value /etc/neutron/neutron.conf auth_host
#ini_unset_value /etc/neutron/neutron.conf auth_protocol
# TODO: Enable separate account for login.
#openstack-configure set /etc/neutron/neutron.conf keystone_authtoken admin_user neutron
#openstack-configure set /etc/neutron/neutron.conf keystone_authtoken admin_password \
#    "$(get_debconf_value "openstack" "keystone/password/neutron")"
#openstack-configure set /etc/neutron/neutron.conf keystone_authtoken admin_tenant_name service

cp /etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini.orig
openstack-configure set /etc/neutron/dhcp_agent.ini DEFAULT force_metadata True
openstack-configure set /etc/neutron/dhcp_agent.ini DEFAULT enable_metadata_network True
openstack-configure set /etc/neutron/dhcp_agent.ini DEFAULT dnsmasq_dns_servers 10.0.0.254
openstack-configure set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata True
openstack-configure set /etc/neutron/dhcp_agent.ini DEFAULT ovs_integration_bridge br-physical

cp /etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini.orig
openstack-configure set /etc/neutron/l3_agent.ini DEFAULT rpc_workers 5
openstack-configure set /etc/neutron/l3_agent.ini DEFAULT rpc_state_report_workers 5
openstack-configure set /etc/neutron/l3_agent.ini DEFAULT external_network_bridge br-provider
openstack-configure set /etc/neutron/l3_agent.ini DEFAULT ovs_integration_bridge br-physical

cp /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.origp
openstack-configure set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs bridge_mappings br-provider
openstack-configure set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs integration_bridge br-physical
openstack-configure set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs local_ip "${ip}"

cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.orig
openstack-configure set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver iptables_hybrid
OLD="$(openstack-configure get /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers)"
[ -n "${OLD}" ] && OLD="${OLD},"
openstack-configure set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers "${OLD}vlan"
openstack-configure set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security
OLD="$(openstack-configure get /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks)"
[ -n "${OLD}" ] && OLD="${OLD},"
openstack-configure set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks "${OLD}provider"
openstack-configure set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan network_vlan_ranges provider

cp /etc/neutron/neutron_lbaas.conf /etc/neutron/neutron_lbaas.conf.orig
#openstack-configure set /etc/neutron/neutron_lbaas.conf service_providers service_provider LOADBALANCERV2:Haproxy:neutron_lbaas.drivers.haproxy.plugin_driver.HaproxyOnHostPluginDriver:default
#openstack-configure set /etc/neutron/neutron_lbaas.conf DEFAULT interface_driver openvswitch # Needs to be done manually
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth auth_url "http://${ctrlnode}:35357/v2.0"
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth admin_username admin
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth admin_password "${neutron_pass}"
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth admin_tenant_name service
penstack-configure set /etc/neutron/neutron_lbaas.conf service_auth region europe-london
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
#LOADBALANCER:Haproxy:neutron.services.loadbalancer.drivers.haproxy.plugin_driver.HaproxyOnHostPluginDriver:default
#if [ "${RET}" != "NO_VALUE" ]; then
#    [ -n "${RET}" ] && RET="${RET},"
#    openstack-configure set /etc/neutron/neutron.conf DEFAULT service_plugins "${RET}???"
#fi

# ======================================================================
# Setup Ironic
cp /etc/ironic/ironic.conf /etc/ironic/ironic.conf.orig
openstack-configure set /etc/ironic/ironic.conf DEFAULT auth_strategy keystone
openstack-configure set /etc/ironic/ironic.conf glance auth_strategy keystone
openstack-configure set /etc/ironic/ironic.conf neutron auth_strategy keystone

# ======================================================================
# Setup Glance.
# TODO: !! Individual service users !!
#cp /etc/glance/glance-scrubber.conf /etc/glance/glance-scrubber.conf.orig
#openstack-configure set /etc/glance/glance-scrubber.conf

# ======================================================================
# Setup MongoDB.
cp /etc/mongodb.conf /etc/mongodb.conf.orig
sed -i "s@^bind_ip[ \t].*@bind_ip = 0.0.0.0@" /etc/mongodb.conf
/etc/init.d/mongodb restart
sleep 10 # Just give it some time..
mongo --host "${ctrlnode}" --eval "
  db = db.getSiblingDB(\"ceilometer\");
  db.addUser({user: \"ceilometer\",
  pwd: \"${mongo_ceilodb_pass}\",
  roles: [ \"readWrite\", \"dbAdmin\" ]})"

# ======================================================================
# Restart all changed servers
# NOTE: Need to do this before we create networks etc.
curl -s http://${LOCALSERVER}/PXEBoot/openstack-services > \
    /etc/init.d/openstack-services
chmod +x /etc/init.d/openstack-services
/etc/init.d/openstack-services restart

# ======================================================================
# Create services and service users.
debconf-get-selections | \
    grep "^openstack[ $(printf '\t')]keystone/password/" | \
    while read line; do
	set -- $(echo "${line}")
        passwd="${4}"
        set -- $(echo "${2}" | sed 's@/@ @g')
        user="${3}"

        # Already created, so skip so we don't error out.
        [ "${user}" = "admin" ] && continue

        openstack user create --project service --project-domain default \
            --password "${passwd}" "${user}"
        openstack role add --project service --user "${user}" admin
    done
openstack role create compute
openstack project create compute
openstack domain create compute
openstack user create --project compute --domain compute --password omed demo
openstack user set --project service admin

# ======================================================================
# Recreate the flavors (with new ones) - the default ones isn't perfect.
set +e # This require that a nova compute exists apparently, so make sure
       # we don't bomb out here.
# Delete all the old ones.
openstack flavor list -f csv --quote none | \
    grep -v 'ID' | \
    while read line; do
	set -- $(echo "${line}" | sed 's@,@ @g')
	# name=2, mem=3, disk=4, vcpus=6
        openstack flavor delete "${2}"
    done

# Create the new flavors.
openstack flavor create --ram   512 --disk  2 --vcpus 1 --disk  5 m1.nano
openstack flavor create --ram  1024 --disk 10 --vcpus 1 --disk  5 m1.tiny
openstack flavor create --ram  2048 --disk 20 --vcpus 1 --disk 10 m1.small
openstack flavor create --ram  4096 --disk 40 --vcpus 1 m1.medium
openstack flavor create --ram  8192 --disk 40 --vcpus 1 m1.large
openstack flavor create --ram 16384 --disk 40 --vcpus 1 m1.xlarge

openstack flavor create --ram  1024 --disk 10 --vcpus 2 --disk 5 m2.tiny
openstack flavor create --ram  2048 --disk 20 --vcpus 2 m2.small
openstack flavor create --ram  4096 --disk 40 --vcpus 2 m2.medium
openstack flavor create --ram  8192 --disk 40 --vcpus 2 m2.large
openstack flavor create --ram 16384 --disk 40 --vcpus 2 m2.xlarge

openstack flavor create --ram  1024 --disk 20 --vcpus 3 --disk  5 m3.tiny
openstack flavor create --ram  2048 --disk 20 --vcpus 3 --disk 10 m3.small
openstack flavor create --ram  4096 --disk 40 --vcpus 3 m3.medium
openstack flavor create --ram  8192 --disk 40 --vcpus 3 m3.large
openstack flavor create --ram 16384 --disk 40 --vcpus 3 m3.xlarge

openstack flavor create --ram  1024 --disk 10 --vcpus 4 --disk  5 m4.tiny
openstack flavor create --ram  2048 --disk 20 --vcpus 4 --disk 10 m4.small
openstack flavor create --ram  4096 --disk 40 --vcpus 4 m4.medium
openstack flavor create --ram  8192 --disk 40 --vcpus 4 m4.large
openstack flavor create --ram 16384 --disk 40 --vcpus 4 m4.xlarge
set -e

# ======================================================================

# Create new security groups.
set +e # This require that a nova compute exists apparently, so make sure
       # we don't bomb out here.
openstack security group create --description "Allow incoming ICMP connections." icmp
openstack security group rule create --proto icmp icmp
openstack security group create --description "Allow incoming SSH connections."  ssh
openstack security group rule create --proto tcp --dst-port 22 ssh
openstack security group rule create --proto udp --dst-port 22 ssh
openstack security group create --description "Allow incoming HTTP connections." http
openstack security group rule create --proto tcp --dst-port 80 http
openstack security group rule create --proto udp --dst-port 80 http
openstack security group create --description "Allow incoming HTTPS connections." https
openstack security group rule create --proto tcp --dst-port 443 https
openstack security group rule create --proto udp --dst-port 443 https
openstack security group create --description "Allow incoming WEB connections (HTTP && HTTPS)." web
openstack security group rule create --proto tcp --dst-port 80 web
openstack security group rule create --proto udp --dst-port 80 web
openstack security group rule create --proto tcp --dst-port 443 web
openstack security group rule create --proto udp --dst-port 443 web
openstack security group create --description "Allow incoming DNS connections." dns
openstack security group rule create --proto tcp --dst-port 42 dns
openstack security group rule create --proto udp --dst-port 42 dns
openstack security group create --description "Allow incoming LDAP connections." ldap
openstack security group rule create --proto tcp --dst-port 389 ldap
openstack security group rule create --proto udp --dst-port 389 ldap
openstack security group create --description "Allow incoming LDAP connections." ldaps
openstack security group rule create --proto tcp --dst-port 636 ldaps
openstack security group rule create --proto udp --dst-port 636 ldaps
openstack security group create --description "Allow incoming MYSQL connections." mysql
openstack security group rule create --proto tcp --dst-port 3306 mysql
openstack security group rule create --proto udp --dst-port 3306 mysql
set -x

# ======================================================================
# Create some key pairs.
set +e # This require that a nova compute exists apparently, so make sure
       # we don't bomb out here.
curl -s http://${LOCALSERVER}/PXEBoot/id_rsa.pub > /var/tmp/id_rsa.pub
openstack keypair create --public-key /var/tmp/id_rsa.pub "Turbo Fredriksson"
rm /var/tmp/id_rsa.pub
set -x

# ======================================================================
# Update the default quota.
set +e # This require that a nova compute exists apparently, so make sure
       # we don't bomb out here.
openstack quota set --key-pairs 2 --fixed-ips 2 --floating-ips 2 \
    --volumes 10 --snapshots 10 --ram 512 --injected-files 10 \
    --gigabytes 100 --secgroups 20 --secgroup-rules 5 default
set -x

# ======================================================================
# Create some host aggregates. Might be nice to have. Eventually.
set +e # This require that a nova compute exists apparently, so make sure
       # we don't bomb out here.
openstack aggregate create --zone nova infra
openstack aggregate create --zone nova devel
openstack aggregate create --zone nova build
openstack aggregate create --zone nova tests
set -x

# ======================================================================
# Create some volume types
set +e # This require that a nova compute exists apparently, so make sure
       # we don't bomb out here.
openstack volume type create --description "Encrypted volumes" --public encrypted
cinder encryption-type-create --cipher aes-xts-plain64 --key_size 512 \
    --control_location front-end encrypted LuksEncryptor
openstack volume type create --description "Local LVM volumes" --public lvm
openstack volume type create --description "Local NFS volumes" --public nfs
openstack volume type set --property volume_backend_name=LVM_iSCSI lvm
openstack volume type set --property volume_backend_name=nfsbackend nfs
# TODO: ?? Create (more) extra spec key-value pairs for these ??
set -x

# ======================================================================
# Setup Open vSwitch.
ovs-vsctl add-br br-physical
#ovs-vsctl add-port br-physical eth1 # TODO: !! This will cut traffic on eth1 !!
ovs-vsctl add-br br-provider
ovs-vsctl add-port br-provider eth0
# TODO:
# 2016-06-20 12:16:11.072 7736 ERROR neutron.agent.ovsdb.impl_vsctl [-] Unable to execute ['ovs-vsctl', '--timeout=10', '--oneline', '--format=json', '--', '--if-exists', 'del-port', 'br-physical', 'patch-tun']. Exception: Exit code: 1; Stdin: ; Stdout: ; Stderr: ovs-vsctl: bridge br-physical does not have a port patch-tun
# 2016-06-20 12:16:11.537 7736 ERROR neutron.plugins.ml2.drivers.openvswitch.agent.ovs_neutron_agent [req-d17e9f19-0a2c-4f86-ac89-7d078842e820 - - - - -] Parsing bridge_mappings failed: Invalid mapping: 'br-provider'. Agent terminated!

# ======================================================================
# Create network(s), routers etc.
# TODO: !! I really need to understand Neutron networking first !!

# Setup the physical network
set +e # This require that a nova compute exists apparently, so make sure
       # we don't bomb out here.
neutron net-create physical --router:external True \
    --provider:physical_network external --provider:network_type flat
neutron subnet-create --name subnet-physical --dns-nameserver 10.0.0.254 \
    --disable-dhcp --ip-version 4 --gateway 10.0.0.254 physical 10.0.0.0/16
neutron router-create --distributed False --ha False router-physical
neutron port-create --name port-physical --vnic-type direct \
    --security-group default --fixed-ip ip_address=10.0.0.200 physical
neutron router-interface-add router-physical port=port-physical

# Setup the first provider network
neutron net-create --shared --provider:network_type gre network-99
neutron subnet-create --name subnet-99 --dns-nameserver 10.0.0.254 \
    --enable-dhcp --ip-version 4 --gateway 10.99.0.1  network-99 10.99.0.0/24

#neutron router-gateway-set --fixed-ip subnet_id=subnet-physical,ip_address=10.0.0.200 \
#    router-physical physical
set -e

# ======================================================================
# Import a bunch of external images.
# Need to run this with nohup in the background, because this will
# take a while!
curl -s http://${LOCALSERVER}/PXEBoot/install_images.sh > \
    /var/tmp/install_images.sh
nohup sh -x /var/tmp/install_images.sh &

# ======================================================================
# Create a LVM on /dev/sdb.
if [ -e "/dev/sdb" ]; then
    dd if=/dev/zero of=/dev/sdb count=1024
    pvcreate /dev/sdb
    for init in /etc/init.d/lvm2*; do $init start; done
    vgcreate blade_center /dev/sdb
fi

# ======================================================================
# Setup Cinder-NFS.
lvcreate -L 50G -n nfs_shares blade_center
mke2fs -F -j /dev/blade_center/nfs_shares
mkdir /shares
mount /dev/blade_center/nfs_shares /shares
echo "$(hostname):/shares" > /etc/cinder/nfs.conf
chown root:cinder /etc/cinder/cinder-nfs.conf
chmod 0640 /etc/cinder/cinder-nfs.conf
cat <<EOF >> /etc/cinder/cinder.conf
volume_backend_name = LVM_iSCSI
iscsi_ip_address = 10.0.4.1

# NFS driver
[nfs]
volume_driver = cinder.volume.drivers.nfs.NfsDriver
volume_group = blade_center
volume_backend_name = nfsbackend
nfs_shares_config = /etc/cinder/cinder-nfs.conf
nfs_sparsed_volumes = true
#nfs_mount_options = 
EOF
echo "/shares$(printf '\t')*.domain.tld(rw,no_subtree_check,no_root_squash)" >> \
    /etc/exports
for init in /etc/init.d/{cinder-*,nfs-kernel-server}; do ${init} restart; done
