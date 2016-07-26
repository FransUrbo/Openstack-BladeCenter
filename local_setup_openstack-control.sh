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

get_net_id () {
    neutron net-list --format csv --column id --column name --quote none | \
        grep "${1}" | \
        sed 's@,.*@@'
}

get_subnet_id () {
    neutron subnet-list --format csv --column id --column name --quote none | \
        grep "${1}" | \
        sed 's@,.*@@'
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

# Get the last part of the IP - 'ip' set in admin-openrc.
ipnr="$(echo "${ip}" | sed 's@.*\.@@')"

set -xe

# ======================================================================

# Preseed debconf (again - the package install(s) zeros out many of
# the passwords).
curl -s http://${LOCALSERVER}/PXEBoot/debconf_openstack-control.txt | \
    sed "s@10\.0\.4\.1@${ip}@" | \
    debconf-set-selections

# Get the wrapper to set variables in config files
curl -s http://${LOCALSERVER}/PXEBoot/openstack-configure > \
    /usr/local/bin/openstack-configure
chmod +x /usr/local/bin/openstack-configure

# Get the MySQL backup script.
curl -s http://${LOCALSERVER}/PXEBoot/backup_openstack_databases.sh > \
    /usr/local/sbin/backup_openstack_databases.sh
chmod +x /usr/local/sbin/backup_openstack_databases.sh
ln -s /usr/local/sbin/backup_openstack_databases.sh /etc/cron.daily/backup_openstack_databases

# Get the script to backup config files.
curl -s http://${LOCALSERVER}/PXEBoot/backup_openstack_config.sh > \
    /usr/local/sbin/backup_openstack_configs.sh
chmod +x /usr/local/sbin/backup_openstack_configs.sh
ln -s /usr/local/sbin/backup_openstack_configs.sh /etc/cron.daily/backup_openstack_configs

# Get a script to cleanup old, dead hosts.
curl -s http://${LOCALSERVER}/PXEBoot/clean_dead_hosts.sh > \
    /usr/local/sbin/clean_dead_hosts.sh
chmod +x /usr/local/sbin/clean_dead_hosts.sh
ln -s /usr/local/sbin/clean_dead_hosts.sh /etc/cron.daily/clean_dead_hosts

# Get a script to fix max_connections in MySQL.
curl -s http://${LOCALSERVER}/PXEBoot/mysql-increase_max_con.sh > \
    /usr/local/sbin/mysql-increase_max_con.sh
chmod +x /usr/local/sbin/mysql-increase_max_con.sh

# Get a wrapper script to restart everything.
curl -s http://${LOCALSERVER}/PXEBoot/openstack-services > \
    /etc/init.d/openstack-services
chmod +x /etc/init.d/openstack-services

# Get and unpack the SSL certificates.
curl -s http://${LOCALSERVER}/PXEBoot/$(hostname)_certs.zip > \
    /var/tmp/certs.zip
chmod 0600 /var/tmp/certs.zip
cd /etc/ssl/certs
unzip -P "$(get_debconf_value "openstack" "certificates/password")" \
    /var/tmp/certs.zip
mv cacert.pem domain.tld.pem
cd /root

set -xe

# ======================================================================

# Get some passwords we'll need to modify configuration with.
neutron_pass="$(get_debconf_value "neutron-common" "/mysql/app-pass")"
rabbit_pass="$(get_debconf_value "designate-common" "/rabbit_password")"
admin_pass="$(get_debconf_value "keystone" "/admin-password")"
aodh_pass="$(get_debconf_value "aodh-common" "/mysql/app-pass")"
glance_pass="$(get_debconf_value "glance-common" "/mysql/app-pass")"
trove_pass="$(get_debconf_value "trove-common" "/mysql/app-pass")"
mongo_ceilodb_pass="$(get_debconf_value "openstack" "mongodb/db_password")"
email="$(get_debconf_value "keystone" "/admin-email")"
ctrlnode="$(get_debconf_value "keystone" "keystone/remote/host")"

if [ -z "${neutron_pass}" -o -z "${rabbit_pass}" -o -z "${admin_pass}" \
    -o -z "${aodh_pass}" -o -z "${mongo_ceilodb_pass}" -o -z "${ctrlnode}" ]
then
    # Just tripple check.
    echo "Can't get necessary passwords!"
    exit 1
fi

# ======================================================================

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

if [ -f /root/admin-openrc ]; then
    . /root/admin-openrc
else
    echo "WARNING: No /root/admin-openrc."
fi
EOF

# Get the ssh key for Cinder and Nova.
curl -s http://${LOCALSERVER}/PXEBoot/id_rsa-control > /etc/cinder/sshkey
chown cinder:root /etc/cinder/sshkey ; chmod 0600 /etc/cinder/sshkey

# RabbitMQ is notoriously sucky and unstable and crashes all the effin time!
# So install a script that checks it once a minut and if it's dead, restart
# it.
curl -s http://${LOCALSERVER}/PXEBoot/check_rabbitmq.sh > \
    /usr/local/sbin/check_rabbitmq.sh
chmod +x /usr/local/sbin/check_rabbitmq.sh
echo "*/1 * * * *	root	/usr/local/sbin/check_rabbitmq.sh" > \
    /etc/cron.d/rabbitmq

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
#openstack-configure set /etc/keystone/keystone.conf ldap url ldap://${LOCALSERVER}
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
#http://docs.openstack.org/admin-guide/keystone_integrate_with_ldap.html
#TODO: [...] and more LDAP stuff..
#ini_unset_value /etc/keystone/keystone.conf admin_token # TODO: ?? Nothing works without this ??

# Configure Designate.
cp /etc/designate/designate.conf /etc/designate/designate.conf.orig
openstack-configure set /etc/designate/designate.conf DEFAULT auth_strategy keystone
openstack-configure set /etc/designate/designate.conf service:api auth_strategy keystone
openstack-configure set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_userid openstack
openstack-configure set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_password "${rabbit_pass}"
openstack-configure set /etc/designate/designate.conf oslo_messaging_rabbit rabbit_hosts "${ctrlnode}"
openstack-configure set /etc/designate/designate.conf service:central managed_resource_email "${email}"
openstack-configure set /etc/designate/designate.conf pool_manager_cache:memcache memcached_servers "${ctrlnode}:11211"
openstack-configure set /etc/designate/designate.conf network_api:neutron endpoints "europe-london\|http://${ctrlnode}:9696/"
openstack-configure set /etc/designate/designate.conf network_api:neutron admin_username admin
openstack-configure set /etc/designate/designate.conf network_api:neutron admin_password "${neutron_pass}"
openstack-configure set /etc/designate/designate.conf network_api:neutron auth_url "http://${ctrlnode}:35357/v2.0"
openstack-configure set /etc/designate/designate.conf network_api:neutron admin_tenant_name service
openstack-configure set /etc/designate/designate.conf network_api:neutron auth_strategy keystone
openstack-configure set /etc/designate/designate.conf service:pool_manager cache_driver memcache

# https://bugs.launchpad.net/designate/+bug/1604043
openstack-configure set /etc/designate/designate.conf service:api enable_api_v2 True
openstack endpoint list --format csv --colum ID --column URL --quote none | \
    grep 9001 | \
    sed 's@,.*@@' | \
    while read endpoint; do
	openstack endpoint set --url http://10.0.4.1:9001/ "${endpoint}"
    done

# Configure Manila.
cp /etc/manila/manila.conf /etc/manila/manila.conf.orig
openstack-configure set /etc/manila/manila.conf DEFAULT driver_handles_share_servers True
openstack-configure set /etc/manila/manila.conf DEFAULT service_instance_user True
openstack-configure set /etc/manila/manila.conf DEFAULT storage_availability_zone nova
openstack-configure set /etc/manila/manila.conf DEFAULT rpc_backend rabbit
openstack-configure set /etc/manila/manila.conf DEFAULT default_share_type default_share_type
openstack-configure set /etc/manila/manila.conf DEFAULT rootwrap_config /etc/manila/rootwrap.conf
openstack-configure set /etc/manila/manila.conf DEFAULT auth_strategy keystone
openstack-configure set /etc/manila/manila.conf DEFAULT memcached_servers "${ctrlnode}:11211"
openstack-configure set /etc/manila/manila.conf DEFAULT my_ip "${ip}"
openstack-configure set /etc/manila/manila.conf DEFAULT enabled_share_backends lvm
openstack-configure set /etc/manila/manila.conf DEFAULT enabled_share_protocols NFS,CIFS
openstack-configure set /etc/manila/manila.conf cinder auth_url "http://${ctrlnode}:8776/v2"
openstack-configure set /etc/manila/manila.conf cinder password "$(get_debconf_value "openstack" "keystone/password/cinder")"
openstack-configure set /etc/manila/manila.conf cinder project_domain_name default
openstack-configure set /etc/manila/manila.conf cinder project_name service
openstack-configure set /etc/manila/manila.conf cinder user_domain_name default
openstack-configure set /etc/manila/manila.conf cinder username cinder
openstack-configure set /etc/manila/manila.conf keystone_authtoken region_name europe-london
openstack-configure set /etc/manila/manila.conf keystone_authtoken memcached_servers "${ctrlnode}:11211"
openstack-configure set /etc/manila/manila.conf keystone_authtoken auth_port 35357
openstack-configure set /etc/manila/manila.conf neutron auth_url "http://${ctrlnode}:9696/"
openstack-configure set /etc/manila/manila.conf neutron password "${neutron_pass}"
openstack-configure set /etc/manila/manila.conf neutron project_domain_name default
openstack-configure set /etc/manila/manila.conf neutron project_name service
openstack-configure set /etc/manila/manila.conf neutron user_domain_name default
openstack-configure set /etc/manila/manila.conf neutron username neutron
openstack-configure set /etc/manila/manila.conf nova auth_url "http://${ctrlnode}:8774/v2"
openstack-configure set /etc/manila/manila.conf nova password "$(get_debconf_value "openstack" "keystone/password/nova")"
openstack-configure set /etc/manila/manila.conf nova project_domain_name default
openstack-configure set /etc/manila/manila.conf nova project_name service
openstack-configure set /etc/manila/manila.conf nova user_domain_name domain
openstack-configure set /etc/manila/manila.conf nova username nova
cat <<EOF >> /etc/manila/manila.conf

# http://docs.openstack.org/mitaka/config-reference/shared-file-systems/drivers/lvm-driver.html
[lvm]
share_backend_name = LVM
share_driver = manila.share.drivers.lvm.LVMShareDriver
driver_handles_share_servers = False
lvm_share_volume_group = blade_center
lvm_share_export_ip = 10.0.4.1
lvm_share_helpers = CIFS=manila.share.drivers.helpers.CIFSHelperUserAccess, NFS=manila.share.drivers.helpers.NFSHelper
EOF

# Configure Nova.
cp /etc/nova/nova.conf /etc/nova/nova.conf.orig
openstack-configure set /etc/nova/nova.conf DEFAULT auth_strategy keystone
openstack-configure set /etc/nova/nova.conf DEFAULT dmz_net 10.99.0.0
openstack-configure set /etc/nova/nova.conf DEFAULT dmz_mask 255.255.255.0
openstack-configure set /etc/nova/nova.conf DEFAULT pybasedir /usr/lib/python2.7/dist-packages
openstack-configure set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
openstack-configure set /etc/nova/nova.conf DEFAULT use_neutron True
openstack-configure set /etc/nova/nova.conf DEFAULT memcached_servers "${ctrlnode}:11211"
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
openstack-configure set /etc/nova/nova.conf DEFAULT dhcp_lease_time $(expr 60 \* 60 \* 6)
openstack-configure set /etc/nova/nova.conf DEFAULT use_single_default_gateway true
openstack-configure set /etc/nova/nova.conf DEFAULT linuxnet_ovs_integration_bridge br-provider
# TODO: [...] lots of networking/nat stuff after that option..
openstack-configure set /etc/nova/nova.conf DEFAULT instance_usage_audit True
openstack-configure set /etc/nova/nova.conf DEFAULT instance_usage_audit_period hour
openstack-configure set /etc/nova/nova.conf DEFAULT notify_on_state_change vm_and_task_state
openstack-configure set /etc/nova/nova.conf DEFAULT driver messagingv2
openstack-configure set /etc/nova/nova.conf DEFAULT rpc_backend rabbit
openstack-configure set /etc/nova/nova.conf DEFAULT cpu_allocation_ratio 8.0
openstack-configure set /etc/nova/nova.conf DEFAULT ram_allocation_ratio 1.0
openstack-configure set /etc/nova/nova.conf DEFAULT disk_allocation_ratio 3.0
openstack-configure set /etc/nova/nova.conf DEFAULT default_ephemeral_format xfs
openstack-configure set /etc/nova/nova.conf DEFAULT public_interface eth1
openstack-configure set /etc/nova/nova.conf DEFAULT service_neutron_metadata_proxy true
openstack-configure set /etc/nova/nova.conf DEFAULT neutron_metadata_proxy_shared_secret \
    "$(get_debconf_value "neutron-metadata-agent" "/metadata_secret")"
openstack-configure set /etc/nova/nova.conf DEFAULT metadata_host \$my_ip
openstack-configure set /etc/nova/nova.conf DEFAULT metadata_listen_port 8775
#openstack-configure set /etc/nova/nova.conf DEFAULT metadata_workers 5
openstack-configure set /etc/nova/nova.conf DEFAULT use_forwarded_for true
openstack-configure set /etc/nova/nova.conf DEFAULT multi_host true
openstack-configure set /etc/nova/nova.conf DEFAULT dhcp_domain openstack.domain.tld
openstack-configure set /etc/nova/nova.conf barbican os_region_name europe-london
openstack-configure set /etc/nova/nova.conf cinder cross_az_attach True
openstack-configure set /etc/nova/nova.conf cinder os_region_name europe-london
#openstack-configure set /etc/nova/nova.conf keystone_authtoken auth_uri "http://${ctrlnode}:5000/v3"
#openstack-configure set /etc/nova/nova.conf keystone_authtoken identity_uri "http://${ctrlnode}:35357/v3"
openstack-configure set /etc/nova/nova.conf keystone_authtoken auth_host "${ctrlnode}"
openstack-configure set /etc/nova/nova.conf keystone_authtoken auth_version 3
openstack-configure set /etc/nova/nova.conf keystone_authtoken auth_port 35357
openstack-configure set /etc/nova/nova.conf keystone_authtoken auth_protocol http
openstack-configure set /etc/nova/nova.conf keystone_authtoken http_connect_timeout 5
openstack-configure set /etc/nova/nova.conf keystone_authtoken http_request_max_retries 3
openstack-configure set /etc/nova/nova.conf keystone_authtoken region_name europe-london
openstack-configure set /etc/nova/nova.conf neutron url "http://${ctrlnode}:9696/"
openstack-configure set /etc/nova/nova.conf neutron username neutron
openstack-configure set /etc/nova/nova.conf neutron password \
    "$(get_debconf_value "openstack" "keystone/password/neutron")"
openstack-configure set /etc/nova/nova.conf neutron region_name europe-london
openstack-configure set /etc/nova/nova.conf neutron project_domain_name default
openstack-configure set /etc/nova/nova.conf neutron project_name service
openstack-configure set /etc/nova/nova.conf neutron user_domain_name default
openstack-configure set /etc/nova/nova.conf neutron ovs_bridge br-provider
openstack-configure set /etc/nova/nova.conf neutron tenant_name service
openstack-configure set /etc/nova/nova.conf ironic api_endpoint "http://${ctrlnode}:6385/v1"
openstack-configure set /etc/nova/nova.conf ironic admin_username ironic
openstack-configure set /etc/nova/nova.conf ironic admin_password \
    "$(get_debconf_value "openstack" "keystone/password/ironic")"
openstack-configure set /etc/nova/nova.conf ironic admin_tenant_name service
openstack-configure set /etc/nova/nova.conf glance api_servers "http://${ctrlnode}:9292/"
openstack-configure set /etc/nova/nova.conf glance num_retries 5
openstack-configure set /etc/nova/nova.conf rdp html5_proxy_base_url http://127.0.0.1:6083/
openstack-configure set /etc/nova/nova.conf rdp enabled true
openstack-configure set /etc/nova/nova.conf spice html5proxy_host 0.0.0.0
openstack-configure set /etc/nova/nova.conf spice html5proxy_port 6082
openstack-configure set /etc/nova/nova.conf spice html5proxy_base_url "http://${ctrlnode}:6082/spice_auto.html"
openstack-configure set /etc/nova/nova.conf spice html5proxy_base_url "${ctrlnode}"
openstack-configure set /etc/nova/nova.conf spice server_listen 0.0.0.0
openstack-configure set /etc/nova/nova.conf spice enabled true
openstack-configure set /etc/nova/nova.conf spice agent_enabled false
ini_unset_value /etc/nova/nova.conf default_domain_name
ini_unset_value /etc/nova/nova.conf domain_name

# Configure Zaqar.
cp /etc/zaqar/zaqar.conf /etc/zaqar/zaqar.conf.orig
openstack-configure set /etc/zaqar/zaqar.conf DEFAULT unreliable True
openstack-configure set /etc/zaqar/zaqar.conf DEFAULT auth_strategy keystone
openstack-configure set /etc/zaqar/zaqar.conf "drivers:management_store:mongodb" database zaqar
openstack-configure set /etc/zaqar/zaqar.conf keystone_authtoken memcached_servers "${ctrlnode}:11211"
openstack-configure set /etc/zaqar/zaqar.conf drivers:transport:wsgi bind "${ip}"

# Configure Cinder.
cp /etc/cinder/cinder.conf /etc/cinder/cinder.conf.orig
openstack-configure set /etc/cinder/cinder.conf DEFAULT my_ip "${ip}"
openstack-configure set /etc/cinder/cinder.conf DEFAULT storage_availability_zone nova
openstack-configure set /etc/cinder/cinder.conf DEFAULT default_availability_zone nova
openstack-configure set /etc/cinder/cinder.conf DEFAULT scheduler_driver cinder.scheduler.filter_scheduler.FilterScheduler
# TODO: !! Not yet - as soon as we get Cinder-ZoL plugin to work. !!
#openstack-configure set /etc/cinder/cinder.conf DEFAULT nas_ip 192.168.69.8
#openstack-configure set /etc/cinder/cinder.conf DEFAULT nas_login root
#openstack-configure set /etc/cinder/cinder.conf DEFAULT nas_private_key /etc/cinder/sshkey
#openstack-configure set /etc/cinder/cinder.conf DEFAULT nas_share_path share/Blade_Center
openstack-configure set /etc/cinder/cinder.conf DEFAULT volume_group blade_center
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_target_prefix iqn.2010-10.org.openstack:
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_port 3260
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_iotype blockio
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_write_cache on
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_ip_address \$my_ip
# Cinder can't handle changed {volume,snapshot,backup}_name_template configuration.
# https://bugs.launchpad.net/cinder/+bug/1602644
#openstack-configure set /etc/cinder/cinder.conf DEFAULT volume_name_template '%s'
#openstack-configure set /etc/cinder/cinder.conf DEFAULT snapshot_name_template '%s.snap'
#openstack-configure set /etc/cinder/cinder.conf DEFAULT backup_name_template '%s.back'
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_helper tgtadm
openstack-configure set /etc/cinder/cinder.conf DEFAULT iscsi_protocol iscsi
openstack-configure set /etc/cinder/cinder.conf DEFAULT volume_dd_blocksize 4M
openstack-configure set /etc/cinder/cinder.conf DEFAULT rpc_backend rabbit
openstack-configure set /etc/cinder/cinder.conf DEFAULT auth_strategy keystone
openstack-configure set /etc/cinder/cinder.conf DEFAULT glance_api_servers "http://${ctrlnode}:9292/"
OLD="$(openstack-configure get /etc/cinder/cinder.conf DEFAULT enabled_backends)"
openstack-configure set /etc/cinder/cinder.conf DEFAULT enabled_backends "${OLD:+${OLD},}nfs"
set -i "s@^\(volume_driver[ \t].*\)@#\1@" /etc/cinder/cinder.conf
openstack-configure set /etc/cinder/cinder.conf DEFAULT nfs_shares_config /etc/cinder/nfs.conf
openstack-configure set /etc/cinder/cinder.conf DEFAULT nfs_sparsed_volumes true
openstack-configure set /etc/cinder/cinder.conf DEFAULT enable_v1_api true
openstack-configure set /etc/cinder/cinder.conf DEFAULT enable_v2_api true
openstack-configure set /etc/cinder/cinder.conf DEFAULT enable_v3_api true
openstack-configure set /etc/cinder/cinder.conf DEFAULT glance_host \$my_ip
openstack-configure set /etc/cinder/cinder.conf DEFAULT glance_port 9292
openstack-configure set /etc/cinder/cinder.conf DEFAULT default_volume_type lvm
openstack-configure set /etc/cinder/cinder.conf DEFAULT os_region_name europe-london
openstack-configure set /etc/cinder/cinder.conf DEFAULT osapi_volume_listen 0.0.0.0
openstack-configure set /etc/cinder/cinder.conf DEFAULT allow_availability_zone_fallback true
openstack-configure set /etc/cinder/cinder.conf DEFAULT image_volume_cache_enabled true
openstack-configure set /etc/cinder/cinder.conf oslo_messaging_notifications driver messagingv2
openstack-configure set /etc/cinder/cinder.conf keystone_authtoken memcached_servers "${ctrlnode}:11211"
openstack-configure set /etc/cinder/cinder.conf keystone_authtoken auth_uri "http://${ctrlnode}:5000/v3"
openstack-configure set /etc/cinder/cinder.conf keystone_authtoken region_name europe-london
openstack-configure set /etc/cinder/cinder.conf lvm volume_group blade_center
openstack-configure set /etc/cinder/cinder.conf database use_db_reconnect true
#TODO: ?? Enable this ??
echo "#*/5 * * * *	/usr/bin/cinder-volume-usage-audit --send_actions" > \
    /etc/cron.d/cinder-volume-usage-audit

# ======================================================================
# Configure Glance.
cp /etc/glance/glance-api.conf /etc/glance/glance-api.conf.orig
openstack-configure set /etc/glance/glance-api.conf DEFAULT rpc_backend rabbit
openstack-configure set /etc/glance/glance-api.conf DEFAULT registry_host "${ip}"
openstack-configure set /etc/glance/glance-api.conf DEFAULT metadata_encryption_key \
    "$(get_debconf_value "openstack" "glance/metadata_encryption_key")"
openstack-configure set /etc/glance/glance-api.conf database use_db_reconnect true
# TODO: Put images in Cinder
#openstack-configure set /etc/glance/glance-api.conf glance_store stores cinder,file,http
#openstack-configure set /etc/glance/glance-api.conf glance_store default_store cinder
openstack-configure set /etc/glance/glance-api.conf glance_store cinder_os_region_name europe-london
openstack-configure set /etc/glance/glance-api.conf glance_store cinder_store_auth_address "${ip}"
openstack-configure set /etc/glance/glance-api.conf glance_store cinder_store_user_name cinder
openstack-configure set /etc/glance/glance-api.conf glance_store cinder_store_password \
    "$(get_debconf_value "cinder-common" "cinder/admin-password")"
openstack-configure set /etc/glance/glance-api.conf glance_store cinder_store_project_name service
# TODO: Use S3 for image repository
#openstack-configure set /etc/glance/glance-api.conf glance_store s3_store_host ???
#openstack-configure set /etc/glance/glance-api.conf glance_store s3_store_access_key ???
#openstack-configure set /etc/glance/glance-api.conf glance_store s3_store_secret_key ???
#openstack-configure set /etc/glance/glance-api.conf glance_store s3_store_bucket ???
#openstack-configure set /etc/glance/glance-api.conf glance_store s3_store_object_buffer_dir /var/lib/glance/images
#openstack-configure set /etc/glance/glance-api.conf glance_store s3_store_create_bucket_on_put true
openstack-configure set /etc/glance/glance-api.conf oslo_messaging_notifications driver messagingv2
openstack-configure set /etc/glance/glance-api.conf keystone_authtoken memcached_servers "${ctrlnode}:11211"

cp /etc/glance/glance-cache.conf /etc/glance/glance-cache.conf.orig
openstack-configure set /etc/glance/glance-cache.conf DEFAULT metadata_encryption_key \
    "$(get_debconf_value "openstack" "glance/metadata_encryption_key")"
openstack-configure set /etc/glance/glance-cache.conf DEFAULT digest_algorithm sha512
openstack-configure set /etc/glance/glance-cache.conf DEFAULT image_cache_dir /var/lib/glance/cache
openstack-configure set /etc/glance/glance-cache.conf DEFAULT registry_host "${ip}"

cp /etc/glance/glance-glare.conf /etc/glance/glance-glare.conf.orig
openstack-configure set /etc/glance/glance-glare.conf DEFAULT bind_host "${ip}"
openstack-configure set /etc/glance/glance-glare.conf database connection "mysql+pymysql://glance:${glance_pass}@${ctrlnode}/glance"
openstack-configure set /etc/glance/glance-glare.conf database use_db_reconnect true
# TODO: Put images in Cinder
#openstack-configure set /etc/glance/glance-glare.conf glance_store stores cinder,file,http
#openstack-configure set /etc/glance/glance-glare.conf glance_store default_store cinder
# TODO: Use S3 for image repository
#openstack-configure set /etc/glance/glance-glare.conf glance_store s3_store_host ???
#openstack-configure set /etc/glance/glance-glare.conf glance_store s3_store_access_key ???
#openstack-configure set /etc/glance/glance-glare.conf glance_store s3_store_secret_key ???
#openstack-configure set /etc/glance/glance-glare.conf glance_store s3_store_bucket ???
#openstack-configure set /etc/glance/glance-glare.conf glance_store s3_store_object_buffer_dir /var/lib/glance/images
#openstack-configure set /etc/glance/glance-glare.conf glance_store s3_store_create_bucket_on_put true
openstack-configure set /etc/glance/glance-glare.conf glance_store cinder_os_region_name europe-london
openstack-configure set /etc/glance/glance-glare.conf glance_store cinder_store_auth_address "${ip}"
openstack-configure set /etc/glance/glance-glare.conf glance_store cinder_store_user_name cinder
openstack-configure set /etc/glance/glance-glare.conf glance_store cinder_store_password \
    "$(get_debconf_value "cinder-common" "cinder/admin-password")"
openstack-configure set /etc/glance/glance-glare.conf glance_store cinder_store_project_name service
openstack-configure set /etc/glance/glance-glare.conf keystone_authtoken region_name europe-london
openstack-configure set /etc/glance/glance-glare.conf keystone_authtoken memcached_servers "${ctrlnode}:11211"
openstack-configure set /etc/glance/glance-glare.conf keystone_authtoken auth_host "${ip}"
openstack-configure set /etc/glance/glance-glare.conf keystone_authtoken auth_protocol http
openstack-configure set /etc/glance/glance-glare.conf keystone_authtoken admin_user glance
openstack-configure set /etc/glance/glance-glare.conf keystone_authtoken admin_password \
    "$(get_debconf_value "glance-common" "glance/admin-password")"
openstack-configure set /etc/glance/glance-glare.conf keystone_authtoken admin_tenant_name service
openstack-configure set /etc/glance/glance-glare.conf database connection "mysql+pymysql://glance:${glance_pass}@${ctrlnode}/glance"
openstack-configure set /etc/glance/glance-glare.conf database use_db_reconnect true

cp /etc/glance/glance-registry.conf /etc/glance/glance-registry.conf.orig
openstack-configure set /etc/glance/glance-registry.conf DEFAULT bind_host "${ip}"
openstack-configure set /etc/glance/glance-registry.conf database use_db_reconnect true
# TODO: Put images in Cinder
#openstack-configure set /etc/glance/glance-registry.conf glance_store stores cinder,file,http
#openstack-configure set /etc/glance/glance-registry.conf glance_store default_store cinder
# TODO: Use S3 for image repository
#openstack-configure set /etc/glance/glance-registry.conf glance_store s3_store_host ???
#openstack-configure set /etc/glance/glance-registry.conf glance_store s3_store_access_key ???
#openstack-configure set /etc/glance/glance-registry.conf glance_store s3_store_secret_key ???
#openstack-configure set /etc/glance/glance-registry.conf glance_store s3_store_bucket ???
#openstack-configure set /etc/glance/glance-registry.conf glance_store s3_store_object_buffer_dir /var/lib/glance/images
#openstack-configure set /etc/glance/glance-registry.conf glance_store s3_store_create_bucket_on_put true
openstack-configure set /etc/glance/glance-registry.conf glance_store cinder_os_region_name europe-london
openstack-configure set /etc/glance/glance-registry.conf glance_store cinder_store_auth_address "${ip}"
openstack-configure set /etc/glance/glance-registry.conf glance_store cinder_store_user_name cinder
openstack-configure set /etc/glance/glance-registry.conf glance_store cinder_store_password \
    "$(get_debconf_value "cinder-common" "cinder/admin-password")"
openstack-configure set /etc/glance/glance-registry.conf glance_store cinder_store_project_name service
openstack-configure set /etc/glance/glance-registry.conf keystone_authtoken region_name europe-london
openstack-configure set /etc/glance/glance-registry.conf keystone_authtoken memcached_servers "${ctrlnode}:11211"
openstack-configure set /etc/glance/glance-registry.conf oslo_messaging_notifications driver messagingv2
openstack-configure set /etc/glance/glance-registry.conf oslo_messaging_rabbit rabbit_host "${ctrlnode}"
openstack-configure set /etc/glance/glance-registry.conf oslo_messaging_rabbit rabbit_userid openstack
openstack-configure set /etc/glance/glance-registry.conf oslo_messaging_rabbit rabbit_password \
    "$(get_debconf_value "glance-common" "glance/rabbit_password")"

cp /etc/glance/glance-scrubber.conf /etc/glance/glance-scrubber.conf.orig
openstack-configure set /etc/glance/glance-scrubber.conf DEFAULT digest_algorithm sha512
openstack-configure set /etc/glance/glance-scrubber.conf DEFAULT metadata_encryption_key \
    "$(get_debconf_value "openstack" "glance/metadata_encryption_key")"
openstack-configure set /etc/glance/glance-scrubber.conf DEFAULT daemon true
openstack-configure set /etc/glance/glance-scrubber.conf DEFAULT registry_host "${ip}"
openstack-configure set /etc/glance/glance-scrubber.conf database connection "mysql+pymysql://glance:${glance_pass}@${ctrlnode}/glance"
openstack-configure set /etc/glance/glance-scrubber.conf database use_db_reconnect true

# Configure Barbican.
cp /etc/barbican/barbican.conf /etc/barbican/barbican.conf.orig
openstack-configure set /etc/barbican/barbican.conf DEFAULT metadata_encryption_key \
    "$(get_debconf_value "openstack" "glance/metadata_encryption_key")"

# Configure Ceilometer.
cp /etc/ceilometer/ceilometer.conf /etc/ceilometer/ceilometer.conf.orig
openstack-configure set /etc/ceilometer/ceilometer.conf DEFAULT rpc_backend rabbit
openstack-configure set /etc/ceilometer/ceilometer.conf keystone_authtoken memcached_servers "${ctrlnode}:11211"
openstack-configure set /etc/ceilometer/ceilometer.conf database connection "mongodb://ceilometer:${mongo_ceilodb_pass}@${ctrlnode}:27017/ceilometer"
# TODO: 2h?
openstack-configure set /etc/ceilometer/ceilometer.conf database metering_time_to_live 7200
openstack-configure set /etc/ceilometer/ceilometer.conf database event_time_to_live 7200

# Configure Aodh.
cp /etc/aodh/aodh.conf /etc/aodh/aodh.conf.orig
openstack-configure set /etc/aodh/aodh.conf DEFAULT rpc_backend rabbit
openstack-configure set /etc/aodh/aodh.conf oslo_messaging_rabbit rabbit_host "${ctrlnode}"
openstack-configure set /etc/aodh/aodh.conf oslo_messaging_rabbit rabbit_userid openstack
openstack-configure set /etc/aodh/aodh.conf oslo_messaging_rabbit rabbit_password "${rabbit_pass}"
openstack-configure set /etc/aodh/aodh.conf database connection "mysql+pymysql://aodh:${aodh_pass}@${ctrlnode}/aodh"
openstack-configure set /etc/aodh/aodh.conf keystone_authtoken memcached_servers "${ctrlnode}:11211"
#openstack-configure set /etc/aodh/aodh.conf keystone_authtoken admin_password "${admin_pass}"

# Configure Neutron.
cp /etc/neutron/neutron.conf /etc/neutron/neutron.conf.orig
openstack-configure set /etc/neutron/neutron.conf DEFAULT bind_host 0.0.0.0
openstack-configure set /etc/neutron/neutron.conf DEFAULT default_availability_zones nova
openstack-configure set /etc/neutron/neutron.conf DEFAULT availability_zone nova
openstack-configure set /etc/neutron/neutron.conf DEFAULT core_plugin neutron.plugins.ml2.plugin.Ml2Plugin
openstack-configure set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_status_changes True
openstack-configure set /etc/neutron/neutron.conf DEFAULT notify_nova_on_port_data_changes True
openstack-configure set /etc/neutron/neutron.conf DEFAULT interface_driver openvswitch
openstack-configure set /etc/neutron/neutron.conf DEFAULT metadata_proxy_shared_secret \
    "$(get_debconf_value "neutron-metadata-agent" "neutron-metadata/metadata_secret")"
OLD="$(openstack-configure get /etc/neutron/neutron.conf DEFAULT service_plugins)"
# NOTE: Using "lbaasv2" gives "Plugin 'lbaasv2' not found".
# TODO: The package is called 'neutron-lbaasv2-agent', not 'neutron-lbaas-agent'!
# TODO: !! Install and enable VPNaaS as soon as it's available !!
openstack-configure set /etc/neutron/neutron.conf DEFAULT service_plugins \
    "${OLD:+${OLD},}lbaas,neutron.services.firewall.fwaas_plugin.FirewallPlugin"
openstack-configure set /etc/neutron/neutron.conf DEFAULT dns_domain openstack.domain.tld.
openstack-configure set /etc/neutron/neutron.conf DEFAULT external_dns_driver designate
openstack-configure set /etc/neutron/neutron.conf DEFAULT agent_down_time 120
openstack-configure set /etc/neutron/neutron.conf keystone_authtoken auth_host openstack.domain.tld
openstack-configure set /etc/neutron/neutron.conf keystone_authtoken auth_port 35357
openstack-configure set /etc/neutron/neutron.conf keystone_authtoken http_connect_timeout 5
openstack-configure set /etc/neutron/neutron.conf keystone_authtoken http_request_max_retries 3
openstack-configure set /etc/neutron/neutron.conf keystone_authtoken project_name service
openstack-configure set /etc/neutron/neutron.conf keystone_authtoken tenant_name neutron
ini_unset_value /etc/neutron/neutron.conf user_domain_id
openstack-configure set /etc/neutron/neutron.conf keystone_authtoken region_name europe-london
# TODO: !! These four don't seem to work !!
#openstack-configure set /etc/neutron/neutron.conf keystone_authtoken auth_uri "http://${ctrlnode}:5000/v3"
#openstack-configure set /etc/neutron/neutron.conf keystone_authtoken identity_uri "http://${ctrlnode}:35357/"
#ini_unset_value /etc/neutron/neutron.conf auth_host
#ini_unset_value /etc/neutron/neutron.conf auth_protocol
openstack-configure set /etc/neutron/neutron.conf nova auth_url "http://${ctrlnode}:5000/v3"
openstack-configure set /etc/neutron/neutron.conf nova project_name service
openstack-configure set /etc/neutron/neutron.conf oslo_messaging_notifications driver \
    neutron.services.metering.drivers.iptables.iptables_driver.IptablesMeteringDriver
openstack-configure set /etc/neutron/neutron.conf agent availability_zone nova
openstack-configure set /etc/neutron/neutron.conf agent report_interval 60
openstack-configure set /etc/neutron/neutron.conf database use_db_reconnect true
ini_unset_value /etc/neutron/neutron.conf domain_name
cat <<EOF >> /etc/neutron/neutron.conf

# http://docs.openstack.org/mitaka/networking-guide/adv-config-dns.html
[designate]
url = http://openstack.domain.tld:9001/v2
admin_auth_url = http://openstack.domain.tld:35357/v3
admin_username = neutron
admin_password = ${neutron_pass}
admin_tenant_name = service
allow_reverse_dns_lookup = False
ipv4_ptr_zone_prefix_size = 24
#ipv6_ptr_zone_prefix_size = 116
EOF

cp /etc/neutron/dhcp_agent.ini /etc/neutron/dhcp_agent.ini.orig
openstack-configure set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata True
openstack-configure set /etc/neutron/dhcp_agent.ini DEFAULT force_metadata True
openstack-configure set /etc/neutron/dhcp_agent.ini DEFAULT enable_metadata_network False
openstack-configure set /etc/neutron/dhcp_agent.ini DEFAULT dhcp_domain openstack.domain.tld.
openstack-configure set /etc/neutron/dhcp_agent.ini DEFAULT dnsmasq_dns_servers 10.0.4.${ipnr}
openstack-configure set /etc/neutron/dhcp_agent.ini DEFAULT ovs_integration_bridge br-provider

cp /etc/neutron/l3_agent.ini /etc/neutron/l3_agent.ini.orig
openstack-configure set /etc/neutron/l3_agent.ini DEFAULT rpc_workers 5
openstack-configure set /etc/neutron/l3_agent.ini DEFAULT rpc_state_report_workers 5
openstack-configure set /etc/neutron/l3_agent.ini DEFAULT external_network_bridge ""
openstack-configure set /etc/neutron/l3_agent.ini DEFAULT ovs_integration_bridge br-provider

cp /etc/neutron/lbaas_agent.ini /etc/neutron/lbaas_agent.ini.orig
# TODO: !! Get LBaaSv2 working !!
openstack-configure set /etc/neutron/lbaas_agent.ini DEFAULT device_driver \
    neutron_lbaas.services.loadbalancer.drivers.haproxy.namespace_driver.HaproxyNSDriver
#    neutron.services.loadbalancer.drivers.haproxy.namespace_driver.HaproxyNSDriver
openstack-configure set /etc/neutron/lbaas_agent.ini DEFAULT ovs_integration_bridge br-provider
openstack-configure set /etc/neutron/lbaas_agent.ini DEFAULT interface_driver \
    neutron.agent.linux.interface.OVSInterfaceDriver
openstack-configure set /etc/neutron/lbaas_agent.ini DEFAULT haproxy user_group haproxy

cp /etc/neutron/services_lbaas.conf /etc/neutron/services_lbaas.conf.orig
openstack-configure set /etc/neutron/services_lbaas.conf haproxy interface_driver neutron.agent.linux.interface.OVSInterfaceDriver

# TODO: !! Until the package come with this file, we use "cat" below to create it instead !!
#cp /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.orig
#openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT auth_url http://${ip}:5000/v2.0
#openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT auth_region europe-london
#openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT admin_tenant_name service
#openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT admin_user neutron
#openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT admin_password "${neutron_pass}"
#openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT nova_metadata_ip "${ip}"
#openstack-config --set /etc/neutron/metadata_agent.ini DEFAULT metadata_proxy_shared_secret \
#    "$(get_debconf_value "neutron-metadata-agent" "neutron-metadata/metadata_secret")"
#
touch /etc/neutron/metadata_agent.ini.orig
cat <<EOF > /etc/neutron/metadata_agent.ini
[DEFAULT]
bind_port = 8775

auth_url = http://${ctrlnode}:5000/v3
auth_region = europe-london

admin_tenant_name = service
admin_user = neutron
admin_password = ${neutron_pass}

nova_metadata_ip = ${ip}
nova_metadata_protocol = http

metadata_port = 8775
metadata_proxy_shared_secret = $(get_debconf_value "neutron-metadata-agent" "neutron-metadata/metadata_secret")

metadata_workers = 16
metadata_backlog = 4096

cache_url = memory://?default_ttl=5

verbose = True
EOF
cp /etc/neutron/metadata_agent.ini /etc/neutron/metadata_agent.ini.save

cp /etc/neutron/plugins/ml2/openvswitch_agent.ini /etc/neutron/plugins/ml2/openvswitch_agent.ini.orig
openstack-configure set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs bridge_mappings external:br-physical,infrastructure:br-infra
openstack-configure set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs integration_bridge br-provider
openstack-configure set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs tunnel_bridge br-tun
openstack-configure set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs local_ip "${ip}"

cp /etc/neutron/plugins/ml2/ml2_conf.ini /etc/neutron/plugins/ml2/ml2_conf.ini.orig
openstack-configure set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver iptables_hybrid
OLD="$(openstack-configure get /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers)"
openstack-configure set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers "${OLD:+${OLD},}vlan"
openstack-configure set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security,dns
openstack-configure set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks external,infrastructure
openstack-configure set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan network_vlan_ranges external:90:99,infrastructure:100:101
OLD="$(openstack-configure get /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types)"
openstack-configure set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 tenant_network_types "${OLD:+${OLD},}vlan,flat"

cp /etc/neutron/neutron_lbaas.conf /etc/neutron/neutron_lbaas.conf.orig
openstack-configure set /etc/neutron/neutron_lbaas.conf DEFAULT interface_driver openvswitch
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth auth_url "http://${ctrlnode}:35357/v2.0"
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth admin_user neutron
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth admin_password "${neutron_pass}"
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth admin_tenant_name service
openstack-configure set /etc/neutron/neutron_lbaas.conf service_auth region europe-london
# TODO: !! Get LBaaSv2 working !!
openstack-configure set /etc/neutron/neutron_lbaas.conf service_providers service_provider \
    LOADBALANCER:Haproxy:neutron_lbaas.services.loadbalancer.drivers.haproxy.plugin_driver.HaproxyOnHostPluginDriver:default
#    LOADBALANCERV2:Haproxy:neutron_lbaas.drivers.haproxy.plugin_driver.HaproxyOnHostPluginDriver:default

# ======================================================================
# Setup Ironic
cp /etc/ironic/ironic.conf /etc/ironic/ironic.conf.orig
openstack-configure set /etc/ironic/ironic.conf DEFAULT auth_strategy keystone
openstack-configure set /etc/ironic/ironic.conf DEFAULT my_ip "${ip}"
openstack-configure set /etc/ironic/ironic.conf glance  auth_strategy keystone
openstack-configure set /etc/ironic/ironic.conf neutron auth_strategy keystone
openstack-configure set /etc/ironic/ironic.conf amt protocol http
openstack-configure set /etc/ironic/ironic.conf api host_ip "${ip}"
openstack-configure set /etc/ironic/ironic.conf api enable_ssl_api false
openstack-configure set /etc/ironic/ironic.conf database use_db_reconnect true
openstack-configure set /etc/ironic/ironic.conf dhcp dhcp_provider neutron
openstack-configure set /etc/ironic/ironic.conf glance glance_host \$my_ip
openstack-configure set /etc/ironic/ironic.conf glance glance_protocol http
openstack-configure set /etc/ironic/ironic.conf glance glance_api_servers "http://openstack.domain.tld:9292/"
openstack-configure set /etc/ironic/ironic.conf irmc remote_image_share_root /shares
openstack-configure set /etc/ironic/ironic.conf irmc remote_image_server \$my_ip
openstack-configure set /etc/ironic/ironic.conf irmc remote_image_share_type NFS
openstack-configure set /etc/ironic/ironic.conf keystone region_name europe-london
openstack-configure set /etc/ironic/ironic.conf keystone_authtoken auth_host "${ip}"
openstack-configure set /etc/ironic/ironic.conf keystone_authtoken auth_protocol http
openstack-configure set /etc/ironic/ironic.conf keystone_authtoken admin_user ironic
openstack-configure set /etc/ironic/ironic.conf keystone_authtoken admin_password \
    "$(get_debconf_value "ironic-common" "ironic/admin-password")"
openstack-configure set /etc/ironic/ironic.conf keystone_authtoken auth_port 35357
openstack-configure set /etc/ironic/ironic.conf keystone_authtoken http_connect_timeout 5
openstack-configure set /etc/ironic/ironic.conf keystone_authtoken http_request_max_retries 3
openstack-configure set /etc/ironic/ironic.conf keystone_authtoken admin_tenant_name service
openstack-configure set /etc/ironic/ironic.conf keystone_authtoken region_name europe-london
openstack-configure set /etc/ironic/ironic.conf keystone_authtoken memcached_servers "${ctrlnode}:11211"
openstack-configure set /etc/ironic/ironic.conf oslo_messaging_rabbit rabbit_host "${ctrlnode}"
openstack-configure set /etc/ironic/ironic.conf oslo_messaging_rabbit rabbit_userid openstack
openstack-configure set /etc/ironic/ironic.conf oslo_messaging_rabbit rabbit_password "${rabbit_pass}"

# ======================================================================
# Setup Trove.
cp /etc/trove/trove.conf /etc/trove/trove.conf.orig
openstack-configure set /etc/trove/trove.conf database connection "mysql+pymysql://trove:${trove_pass}@${ctrlnode}/trove"
openstack-configure set /etc/trove/trove.conf DEFAULT trove_auth_url "http://${ctrlnode}:5000/v2.0"
openstack-configure set /etc/trove/trove.conf DEFAULT nova_compute_url "http://${ctrlnode}:8774/v2"
openstack-configure set /etc/trove/trove.conf DEFAULT cinder_url "http://${ctrlnode}:8776/v1"
openstack-configure set /etc/trove/trove.conf DEFAULT swift_url "http://${ctrlnode}:8080/v1/AUTH_"
openstack-configure set /etc/trove/trove.conf DEFAULT neutron_url "http://${ctrlnode}:9696/"
openstack-configure set /etc/trove/trove.conf DEFAULT dns_auth_url "http://${ctrlnode}:5000/v2.0"
#openstack-configure set /etc/trove/trove.conf DEFAULT dns_username ???
#openstack-configure set /etc/trove/trove.conf DEFAULT dns_passkey ???
openstack-configure set /etc/trove/trove.conf DEFAULT network_label_regex '.\*'
openstack-configure set /etc/trove/trove.conf DEFAULT os_region_name europe-london
openstack-configure set /etc/trove/trove.conf mysql root_on_create True

cp /etc/trove/trove-taskmanager.conf /etc/trove/trove-taskmanager.conf.orig
#openstack-configure set /etc/trove/trove-taskmanager.conf database connection "mysql+pymysql://trove:${trove_pass}@${ctrlnode}/trove"
#openstack-configure set /etc/trove/trove-taskmanager.conf DEFAULT trove_auth_url "http://${ctrlnode}:35357/v2.0"
#openstack-configure set /etc/trove/trove-taskmanager.conf DEFAULT nova_compute_url "http://${ctrlnode}:8774/v2"
#openstack-configure set /etc/trove/trove-taskmanager.conf DEFAULT cinder_url "http://${ctrlnode}:8776/v2"
##openstack-configure set /etc/trove/trove-taskmanager.conf DEFAULT swift_url "http://${ctrlnode}:8080/v1/AUTH_"
#openstack-configure set /etc/trove/trove-taskmanager.conf DEFAULT neutron_url "http://${ctrlnode}:9696/"
#openstack-configure set /etc/trove/trove-taskmanager.conf DEFAULT os_region_name europe-london
#openstack-configure set /etc/trove/trove-taskmanager.conf DEFAULT nova_proxy_admin_pass \
#    "$(get_debconf_value "trove-api" "/keystone-admin-password")"
#openstack-configure set /etc/trove/trove-taskmanager.conf DEFAULT use_nova_server_volume True
#openstack-configure set /etc/trove/trove-taskmanager.conf DEFAULT mount_point /var/lib/trove/mysql
# TODO: Until the config file contain all relevant templates, just get the whole thing.
curl -s http://${LOCALSERVER}/PXEBoot/trove-taskmanager.conf > /etc/trove/trove-taskmanager.conf

cp /etc/trove/trove-conductor.conf /etc/trove/trove-conductor.conf.orig
openstack-configure set /etc/trove/trove-conductor.conf DEFAULT trove_auth_url "http://${ctrlnode}:5000/v2.0"
openstack-configure set /etc/trove/trove-conductor.conf database connection "mysql+pymysql://trove:${trove_pass}@${ctrlnode}/trove"

cp /etc/trove/trove-guestagent.conf /etc/trove/trove-guestagent.conf.orig
#openstack-configure set /etc/trove/trove-guestagent.conf DEFAULT os_region_name europe-london
#openstack-configure set /etc/trove/trove-guestagent.conf DEFAULT swift_service_type object-store
#openstack-configure set /etc/trove/trove-guestagent.conf DEFAULT log_file trove.log
# TODO: Until the config file contain all relevant templates, just get the whole thing.
curl -s http://${LOCALSERVER}/PXEBoot/trove-guestagent.conf > /etc/trove/trove-guestagent.conf

touch /etc/trove/cloudinit/mysql.cloudinit.orig
curl -s http://${LOCALSERVER}/PXEBoot/mysql.cloudinit > /etc/trove/cloudinit/mysql.cloudinit

echo "trove ALL = NOPASSWD: ALL" > /etc/sudoers.d/trove
mkdir /var/lib/trove/mysql /var/lib/trove/postgresql
chown trove /var/lib/trove/mysql /var/lib/trove/postgresql

# ======================================================================
# Setup Swift.
cp /etc/swift/account-server.conf /etc/swift/account-server.conf.orig
openstack-configure set /etc/swift/account-server.conf DEFAULT devices /swift

cp /etc/swift/object-server.conf /etc/swift/object-server.conf.orig
openstack-configure set /etc/swift/object-server.conf DEFAULT devices /swift

cp /etc/swift/container-server.conf /etc/swift/container-server.conf.orig
openstack-configure set /etc/swift/container-server.conf DEFAULT devices /swift

# ======================================================================
# Setup Senlin.
cp /etc/senlin/senlin.conf /etc/senlin/senlin.conf.orig
#openstack-configure set /etc/senlin/senlin.conf database use_db_reconnect true
#openstack-configure set /etc/senlin/senlin.conf keystone_authtoken region_name europe-london
#openstack-configure set /etc/senlin/senlin.conf keystone_authtoken memcached_servers "${ctrlnode}:11211"
#openstack-configure set /etc/senlin/senlin.conf keystone_authtoken auth_port 35357
#openstack-configure set /etc/senlin/senlin.conf keystone_authtoken auth_type v3password
#openstack-configure set /etc/senlin/senlin.conf keystone_authtoken auth_uri "http://${ctrlnode}:5000/v3"
#openstack-configure set /etc/senlin/senlin.conf keystone_authtoken identity_uri "http://${ctrlnode}:35357"
# TODO: Until the config file contain all relevant templates, just get the whole thing.
curl -s http://${LOCALSERVER}/PXEBoot/senlin.conf > /etc/senlin/senlin.conf

# ======================================================================
# Setup Heat.
cp /etc/heat/heat.conf /etc/heat/heat.conf.orig
openstack-configure set /etc/heat/heat.conf keystone_authtoken auth_version 3
openstack-configure set /etc/heat/heat.conf keystone_authtoken region_name europe-london
openstack-configure set /etc/heat/heat.conf keystone_authtoken memcached_servers "${ctrlnode}:11211"
openstack-configure set /etc/heat/heat.conf keystone_authtoken auth_port 35357
openstack-configure set /etc/heat/heat.conf keystone_authtoken auth_uri "http://${ctrlnode}:5000/v3"
# TODO: Until "heat-api-cfn" does 'the right thing':
#openstack-configure set /etc/heat/heat.conf DEFAULT heat_metadata_server_url "http://${ctrlnode}:8000"
#openstack-configure set /etc/heat/heat.conf DEFAULT heat_waitcondition_server_url http://${ctrlnode}:8000/v1/waitcondition
sed -i "s@^\(\[DEFAULT\]\)@\[DEFAULT\]\\
heat_metadata_server_url = http://${ctrlnode}:8000\\
heat_waitcondition_server_url = http://${ctrlnode}:8000/v1/waitcondition@" \
    /etc/heat/heat.conf

REGION_NAME="europe-london"
SERVICE_NAME="heat-cfn"
SERVICE_DESC="Orchestration CloudFormation"
SERVICE_TYPE="cloudformation"
PKG_ENDPOINT_IP="10.0.4.1"
SERVICE_PORT="8000"
SERVICE_URL="/v1"

openstack service create --name=${SERVICE_NAME} --description="${SERVICE_DESC}" ${SERVICE_TYPE}

openstack endpoint create --region "${REGION_NAME}" ${SERVICE_NAME} public   http://${PKG_ENDPOINT_IP}:${SERVICE_PORT}${SERVICE_URL}
openstack endpoint create --region "${REGION_NAME}" ${SERVICE_NAME} internal http://${PKG_ENDPOINT_IP}:${SERVICE_PORT}${SERVICE_URL}
openstack endpoint create --region "${REGION_NAME}" ${SERVICE_NAME} admin    http://${PKG_ENDPOINT_IP}:${SERVICE_PORT}${SERVICE_URL}

sed -i "s@Instance: m1.small@Instance: m1.3small@" AWS_RDS_DBInstance.yaml
sed -i "s@Instance: m1.large@Instance: m1.5large@" AWS_RDS_DBInstance.yaml
sed -i "s@Instance: m1.xlarge@Instance: m1.6xlarge@" AWS_RDS_DBInstance.yaml
sed -i "s@Instance: m2.xlarge@Instance: m2.4large@" AWS_RDS_DBInstance.yaml
sed -i "s@Instance: m2.2xlarge@Instance: m2.5xlarge@" AWS_RDS_DBInstance.yaml

# ======================================================================
# Setup MongoDB.
cp /etc/mongodb.conf /etc/mongodb.conf.orig
sed -i "s@^bind_ip[ \t].*@bind_ip = 0.0.0.0@" /etc/mongodb.conf
/etc/init.d/mongodb restart
echo "Sleeping 10 seconds to give MongoDB time to start."
sleep 10 # Just give it some time..
mongo --host "${ctrlnode}" --eval "
  db = db.getSiblingDB(\"ceilometer\");
  db.addUser({user: \"ceilometer\",
  pwd: \"${mongo_ceilodb_pass}\",
  roles: [ \"readWrite\", \"dbAdmin\" ]})"

# ======================================================================
# Create a RNDC key for Designate.
rndc-confgen -a -b 512 -c /etc/designate/rndc.key -k designate-key -u designate

# Make sure 'bind' group can access the key.
chown designate:bind /etc/designate/rndc.key
chmod 640 /etc/designate/rndc.key
chgrp bind /etc/designate
chmod g=rx /etc/designate

# Setup Bind9.
cp /etc/bind/named.conf.options /etc/bind/named.conf.options.orig
cat <<EOF > /etc/bind/named.conf.options
options {
	directory "/var/cache/bind";
	forwarders {
		10.0.0.254;
	};
	dnssec-validation auto;
	auth-nxdomain no; # conform to RFC1035
	listen-on-v6 { any; };
	allow-new-zones yes;
	request-ixfr no;
	recursion no;
};

include "/etc/designate/rndc.key";

controls {
        inet 127.0.0.1 allow { localhost; } keys { "designate-key"; };
        inet 10.0.4.${ipnr}  allow { localhost; } keys { "designate-key"; };
};
EOF

# ======================================================================
# Restart all changed servers
# NOTE: Need to do this before we create networks etc.
/etc/init.d/openstack-services restart
service bind9 restart

# ======================================================================
# Sync/upgrade the database to create the missing tables for LBaaSv2.
neutron-db-manage --config-file /etc/neutron/neutron.conf upgrade head

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

# ======================================================================
# Create some volume types
openstack volume type create --description "Encrypted volumes" --public encrypted
cinder encryption-type-create --cipher aes-xts-plain64 --key_size 512 \
    --control_location front-end encrypted LuksEncryptor
openstack volume type create --description "Local LVM volumes" --public lvm
openstack volume type create --description "Local NFS volumes" --public nfs
openstack volume type set --property volume_backend_name=LVM lvm
openstack volume type set --property volume_backend_name=NFS nfs

# ======================================================================
# Setup Open iSCSI.
iscsiadm -m iface -I eth1 --op=new
iscsiadm -m iface -I eth1 --op=update -n iface.vlan_priority -v 1

# ======================================================================
# Create network(s), routers etc.

# ----------------------------------------------------------------------
# Setup the physical (provider) network.
# NOTE: Setting "provider:physical_network" name must match "bridge_mappings"
#       and "network_vlan_ranges" above!
neutron net-create physical --router:external True --shared \
    --provider:physical_network external --provider:network_type flat \
    --availability-zone-hint nova
neutron subnet-create --name subnet-physical --dns-nameserver 10.0.0.254 \
    --disable-dhcp --ip-version 4 --gateway 10.0.0.254 \
    --allocation-pool start=10.0.250.1,end=10.0.255.252 \
    physical 10.0.0.0/16

# ----------------------------------------------------------------------
# Setup the tenant networks.
for net in 97 98 99; do
    neutron net-create "tenant-${net}" --shared --provider:network_type gre \
        --availability-zone-hint nova

    neutron subnet-create --name "subnet-${net}" --dns-nameserver 10.0.0.254 \
        --enable-dhcp --ip-version 4 --gateway "10.${net}.0.1" \
        "tenant-${net}" "10.${net}.0.0/24"
done

# ----------------------------------------------------------------------
# Setup network routers.
# TODO: !! Need >1 l3 agents to do HA !!
# ----------------------------------------------------------------------

# Create the router between these.
neutron router-create --distributed False --ha False provider-tenants

# ----------------------------------------------------------------------
# Create router port on the provider networks.
for net in 97 98 99; do
    neutron port-create --name "port-tenant${net}" --vnic-type normal \
        --fixed-ip ip_address="10.${net}.0.1" "tenant-${net}"

    neutron router-interface-add provider-tenants port="port-tenant${net}"
done

# ----------------------------------------------------------------------
# Set the routers default route to external gateway.
# NOTE: Ths also creates a port on the router.
neutron router-gateway-set --fixed-ip subnet_id=subnet-physical,ip_address=10.0.0.253 \
    provider-tenants physical
set -- $(neutron port-list -c id -c fixed_ips | grep -w 10.0.0.253)
[ -n "${2}" ] && neutron port-update --name port-external "${2}"

# ----------------------------------------------------------------------
# Create the second physical network - Infrastructure.
neutron net-create infrastructure --router:external True --shared \
    --provider:physical_network infrastructure --provider:network_type flat \
    --availability-zone-hint nova

neutron subnet-create --name subnet-infrastructure --dns-nameserver 10.0.0.254 \
    --enable-dhcp --ip-version 4 --gateway 192.168.96.1 \
    --allocation-pool start=192.168.96.2,end=192.168.96.253 \
    infrastructure 192.168.96.0/24

neutron router-create --distributed False --ha False infrastructure

neutron router-gateway-set --fixed-ip subnet_id=subnet-infrastructure,ip_address=192.168.96.254 \
    infrastructure infrastructure
set -- $(neutron port-list -c id -c fixed_ips | grep -w 192.168.96.1)
[ -n "${2}" ] && neutron port-update --name port-infrastructure "${2}"

# ----------------------------------------------------------------------
# Create a load balancer for each of the subnets.
neutron lb-pool-create --lb-method LEAST_CONNECTIONS --name hapool-97 \
    --protocol TCP --subnet-id subnet-97 --provider haproxy
neutron lb-pool-create --lb-method LEAST_CONNECTIONS --name hapool-98 \
    --protocol TCP --subnet-id subnet-98 --provider haproxy
neutron lb-pool-create --lb-method LEAST_CONNECTIONS --name hapool-99 \
    --protocol TCP --subnet-id subnet-99 --provider haproxy

# ----------------------------------------------------------------------
# Create a load balancer monitor.
neutron lb-healthmonitor-create --type PING --timeout 15 --delay 15 \
    --max-retries 5

# ----------------------------------------------------------------------
# Create a VIP port on the loadbalancers
# NOTE: Can't load balance ssh: WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED
neutron lb-vip-create --address 10.97.0.254 --name vip-97 \
    --protocol-port 22 --protocol TCP --subnet-id subnet-97 hapool-97
neutron lb-vip-create --address 10.98.0.254 --name vip-98 \
    --protocol-port 22 --protocol TCP --subnet-id subnet-98 hapool-98
neutron lb-vip-create --address 10.99.0.254 --name vip-99 \
    --protocol-port 22 --protocol TCP --subnet-id subnet-99 hapool-99

# ----------------------------------------------------------------------
# TODO: Add instance(s) to the member list of the hapool.
# NOTE: Can't be done automatic - need to have running instances.
#openstack server list --column Name --column Networks --column Status
#neutron lb-member-create --weight 1 --address ?? --protocol-port 22 \
#    hapool-97

# ----------------------------------------------------------------------
# Setup a Firewall as a Service.
# NOTE: Deny _everything_ to the tenant networks!
#       Must use a floating IP to access the instance(s).
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# Create FWaaS rules.
# Reject everything to all the tenant networks.
# Allow everything to the floating IP network.
for net in 97.0 98.0 99.0 0.250; do
    action="reject"

    for prot in tcp udp icmp; do
        [ "${net}" = "0.250" ] && action="allow"
        if [ "${prot}" = "icmp" ]; then
            dst_port=""
            src_port=""
        else
            dst_port="--destination-port 1:65535"
            src_port="--source-port 1:65535"
        fi

        neutron firewall-rule-create --enabled True --protocol "${prot}" \
            --ip-version 4 --shared --name "fw-rule-${net}-${prot}" \
            --action "${action}" --destination-ip-address "10.${net}.0/24" \
            --source-ip-address 0.0.0.0/0 ${dst_port} ${src_port}
    done
done

# ----------------------------------------------------------------------
# Create a FWaaS policy.
rules="$(neutron firewall-rule-list  --format csv --column id --quote none | \
    grep -v ^id)"
neutron firewall-policy-create --shared --firewall-rules "${rules}" \
    firewall-policy

# ----------------------------------------------------------------------
# Create a FWaaS firewall.
neutron firewall-create --name firewall-tenants --no-routers firewall-policy

# TODO: !! Don't bind the firewall it to a router !!
# NOTE: Need to figure out exactly how to use it and if it works with SGs
#neutron firewall-update --router provider-tenants firewall-tenants

# ======================================================================
# Create a LVM on /dev/sdb.
if [ -e "/dev/sdb" ]; then
    dmsetup remove_all -f
    dd if=/dev/zero of=/dev/sdb bs=512 count=1
    pvcreate -ff -y /dev/sdb
    for init in /etc/init.d/lvm2*; do $init start; done
    vgcreate blade_center /dev/sdb
fi

# ======================================================================
# Recreate the flavors (with new ones) - the default ones isn't perfect.

# Delete all the old ones.
openstack flavor list -f csv --quote none | \
    grep -v 'ID' | \
    while read line; do
	set -- $(echo "${line}" | sed 's@,@ @g')
	# name=2, mem=3, disk=4, vcpus=6
        openstack flavor delete "${2}"
    done

# Create the new flavors.
openstack flavor create --ram   512 --disk  2 --vcpus 1 --disk  5 m1.1nano
openstack flavor create --ram  1024 --disk 10 --vcpus 1 --disk  5 m1.2tiny
openstack flavor create --ram  2048 --disk 20 --vcpus 1 --disk 10 m1.3small
openstack flavor create --ram  4096 --disk 40 --vcpus 1 m1.4medium
openstack flavor create --ram  8192 --disk 40 --vcpus 1 m1.5large
openstack flavor create --ram 16384 --disk 40 --vcpus 1 m1.6xlarge

openstack flavor create --ram  1024 --disk 10 --vcpus 2 --disk 5 m2.1tiny
openstack flavor create --ram  2048 --disk 20 --vcpus 2 m2.2small
openstack flavor create --ram  4096 --disk 40 --vcpus 2 m2.3medium
openstack flavor create --ram  8192 --disk 40 --vcpus 2 m2.4large
openstack flavor create --ram 16384 --disk 40 --vcpus 2 m2.5xlarge

openstack flavor create --ram  1024 --disk 20 --vcpus 3 --disk  5 m3.1tiny
openstack flavor create --ram  2048 --disk 20 --vcpus 3 --disk 10 m3.2small
openstack flavor create --ram  4096 --disk 40 --vcpus 3 m3.3medium
openstack flavor create --ram  8192 --disk 40 --vcpus 3 m3.4large
openstack flavor create --ram 16384 --disk 40 --vcpus 3 m3.5xlarge

openstack flavor create --ram  1024 --disk 10 --vcpus 4 --disk  5 m4.1tiny
openstack flavor create --ram  2048 --disk 20 --vcpus 4 --disk 10 m4.2small
openstack flavor create --ram  4096 --disk 40 --vcpus 4 m4.3medium
openstack flavor create --ram  8192 --disk 40 --vcpus 4 m4.4large
openstack flavor create --ram 16384 --disk 40 --vcpus 4 m4.5xlarge

# ======================================================================

# Create new security groups.
clean_security_group() {
    neutron security-group-rule-list -f csv -c id -c security_group | \
        grep "\"${1}\"" | \
        sed -e 's@"@@g' -e 's@,.*@@' | \
        while read grp; do
	    neutron security-group-rule-delete "${grp}"
	done
}

# Modify the default security group to allow everything.
secgrp="$(neutron security-group-list --column id --column name --format csv --quote none | \
    grep default | sed 's@,.*@@')"
clean_security_group "${secgrp}"
neutron security-group-rule-create --direction egress --protocol tcp --port-range-min  80 \
    --port-range-max 80 --remote-ip-prefix 0.0.0.0/0 "${secgrp}"
neutron security-group-rule-create --direction egress --protocol tcp --port-range-min  53 \
    --port-range-max 53 --remote-ip-prefix 0.0.0.0/0 "${secgrp}"
neutron security-group-rule-create --direction egress --protocol udp --port-range-min  53 \
    --port-range-max 53 --remote-ip-prefix 0.0.0.0/0 "${secgrp}"

openstack security group create --description "Allow all incoming and outgoing connections." all
clean_security_group all
neutron security-group-rule-create --direction ingress --protocol tcp --port-range-min 1 \
    --port-range-max 65535 --remote-ip-prefix 0.0.0.0/0 all
neutron security-group-rule-create --direction ingress --protocol udp --port-range-min 1 \
    --port-range-max 65535 --remote-ip-prefix 0.0.0.0/0 all
neutron security-group-rule-create --direction egress  --protocol tcp --port-range-min 1 \
    --port-range-max 65535 --remote-ip-prefix 0.0.0.0/0 all
neutron security-group-rule-create --direction egress  --protocol udp --port-range-min 1 \
    --port-range-max 65535 --remote-ip-prefix 0.0.0.0/0 all
neutron security-group-rule-create --direction ingress --protocol icmp --remote-ip-prefix \
    0.0.0.0/0 all
neutron security-group-rule-create --direction egress  --protocol icmp --remote-ip-prefix \
    0.0.0.0/0 all

openstack security group create --description "Allow incoming SSH connections." ssh
clean_security_group ssh
neutron security-group-rule-create --direction ingress --protocol tcp --port-range-min 22 \
    --port-range-max 22 --remote-ip-prefix 0.0.0.0/0 ssh
neutron security-group-rule-create --direction egress  --protocol udp --port-range-min 22 \
    --port-range-max 22 --remote-ip-prefix 0.0.0.0/0 ssh

openstack security group create --description "Allow incoming HTTP/HTTPS connections." web
clean_security_group web
neutron security-group-rule-create --direction ingress --protocol tcp --port-range-min  80 \
    --port-range-max 80 --remote-ip-prefix 0.0.0.0/0 web
neutron security-group-rule-create --direction ingress --protocol tcp --port-range-min 443 \
    --port-range-max 443 --remote-ip-prefix 0.0.0.0/0 web
neutron security-group-rule-create --direction egress  --protocol udp --port-range-min  80 \
    --port-range-max 80 --remote-ip-prefix 0.0.0.0/0 web
neutron security-group-rule-create --direction egress  --protocol udp --port-range-min 443 \
    --port-range-max 443 --remote-ip-prefix 0.0.0.0/0 web

openstack security group create --description "Allow incoming DNS connections." dns
clean_security_group dns
neutron security-group-rule-create --direction ingress --protocol tcp --port-range-min 53 \
    --port-range-max 53 --remote-ip-prefix 0.0.0.0/0 dns
neutron security-group-rule-create --direction egress  --protocol udp --port-range-min 53 \
    --port-range-max 53 --remote-ip-prefix 0.0.0.0/0 dns

openstack security group create --description "Allow incoming LDAP/LDAPS connections." ldap
clean_security_group ldap
neutron security-group-rule-create --direction ingress --protocol tcp --port-range-min 389 \
    --port-range-max 389 --remote-ip-prefix 0.0.0.0/0 ldap
neutron security-group-rule-create --direction ingress --protocol tcp --port-range-min 636 \
    --port-range-max 636 --remote-ip-prefix 0.0.0.0/0 ldap
neutron security-group-rule-create --direction egress  --protocol udp --port-range-min 389 \
    --port-range-max 389 --remote-ip-prefix 0.0.0.0/0 ldap
neutron security-group-rule-create --direction egress  --protocol udp --port-range-min 636 \
    --port-range-max 636 --remote-ip-prefix 0.0.0.0/0 ldap

openstack security group create --description "Allow incoming MySQL connections." mysql
clean_security_group mysql
neutron security-group-rule-create --direction ingress --protocol tcp --port-range-min 3306 \
    --port-range-max 3306 --remote-ip-prefix 0.0.0.0/0 mysql
neutron security-group-rule-create --direction egress  --protocol udp --port-range-min 3306 \
    --port-range-max 3306 --remote-ip-prefix 0.0.0.0/0 mysql

openstack security group create --description "Allow incoming PostgreSQL connections." psql
clean_security_group psql
neutron security-group-rule-create --direction ingress --protocol tcp --port-range-min 5432 \
    --port-range-max 5432 --remote-ip-prefix 0.0.0.0/0 psql
neutron security-group-rule-create --direction egress  --protocol udp --port-range-min 5432 \
    --port-range-max 5432 --remote-ip-prefix 0.0.0.0/0 psql

openstack security group create --description "Allow incoming/outgoing ICMP connections." icmp
clean_security_group icmp
neutron security-group-rule-create --direction ingress --protocol icmp --remote-ip-prefix \
    0.0.0.0/0 icmp
neutron security-group-rule-create --direction egress  --protocol icmp --remote-ip-prefix \
    0.0.0.0/0 icmp

# ======================================================================
# Create some key pairs.
curl -s http://${LOCALSERVER}/PXEBoot/id_rsa.pub > /var/tmp/id_rsa.pub
openstack keypair create --public-key /var/tmp/id_rsa.pub "Turbo Fredriksson"
rm /var/tmp/id_rsa.pub

# ======================================================================
# Update the default quota.
for proj in default $(openstack project list --column ID --format csv \
    --quote none | grep -v ^ID)
do
    openstack quota set --key-pairs 5 --fixed-ips 20 --floating-ips 50 \
        --volumes 50 --snapshots 10 --ram 10240 --injected-files 10 \
        --gigabytes 100 --secgroups 50 --secgroup-rules 50 --instances 30 \
        "${proj}"

    neutron quota-update --tenant-id "${proj}" --network 5 --subnet 10 \
        --port 50 --router 2 --floatingip 200 --security-group 50 \
        --security-group-rule 50 --vip 50 --health-monitor 50
done

# ======================================================================
# Create some host aggregates. Might be nice to have. Eventually. Maybe.
openstack aggregate create --zone nova infra
openstack aggregate create --zone nova devel
openstack aggregate create --zone nova build
openstack aggregate create --zone nova tests

# ======================================================================
# Create a bunch (20) of floating IPs.
i=0
while [ "${i}" -le 19 ]; do
    openstack ip floating create physical
    i="$(expr "${i}" + 1)"
done

# ======================================================================
# Setup Designate pool and zone.
curl -s http://${LOCALSERVER}/PXEBoot/designate-pool.yaml | \
    sed "s@%NR%@${ipnr}@" > /var/tmp/designate-pool.yaml
designate-manage pool update --file /var/tmp/designate-pool.yaml

designate domain-create --name openstack.domain.tld. \
    --email dnsadmin@openstack.domain.tld
domain_id="$(designate domain-list --format csv --column id --quote none | grep -v ^id)"
designate record-create --name ns${ipnr} --type NS \
    --data ns${ipnr}.openstack.domain.tld. openstack.domain.tld.
designate record-create --name ns${ipnr} --type A --data 10.0.4.${ipnr} \
    openstack.domain.tld.
designate record-create --name openstack.domain.tld. --type A \
    --data 10.0.4.${ipnr} openstack.domain.tld.
for net in physical tenant-97 tenant-98 tenant-99; do
    neutron net-update --dns-domain openstack.domain.tld. "${net}"
done

# ======================================================================
# Setup Manila (Shared File System as a Service).
manila type-create default_share_type False

netid="$(get_net_id "tenant-97")"
subnetid="$(get_subnet_id "subnet-97")"

manila share-network-create --name "network-97" \
    --neutron-net-id "${netid}" --neutron-subnet-id "${subnetid}" \
    --share-type default_share_type #--metadata volume_backend_name=LVM

manila create NFS 2 --public --name "share-97" \
    --availability-zone nova --share-type default_share_type
sleep 5
manila access-allow "share-97" ip 0.0.0.0/0 --access-level rw

# Just for posterity..
manila share-export-location-list "share-${net}"

# ======================================================================
# Setup Cinder-NFS.
lvcreate -L 50G -n nfs_shares blade_center
mke2fs -F -j /dev/blade_center/nfs_shares
mkdir /shares
mount /dev/blade_center/nfs_shares /shares
rmdir /shares/lost+found
echo "$(hostname):/shares" > /etc/cinder/cinder-nfs.conf
chown root:cinder /etc/cinder/cinder-nfs.conf
chmod 0640 /etc/cinder/cinder-nfs.conf
cat <<EOF >> /etc/cinder/cinder.conf
volume_backend_name = LVM
lvm_conf_file = /etc/cinder/cinder-lvm.conf
lvm_type = default

# NFS driver
[nfs]
volume_driver = cinder.volume.drivers.nfs.NfsDriver
volume_group = blade_center
volume_backend_name = NFS
nfs_shares_config = /etc/cinder/cinder-nfs.conf
nfs_sparsed_volumes = true
#nfs_mount_options = 
EOF
cp /etc/exports /etc/exports.orig
echo "/shares$(printf '\t')*.domain.tld(rw,no_subtree_check,no_root_squash)" >> \
    /etc/exports
d=/etc/init.d
for init in $(find ${d}/cinder* ${d}/nfs-kernel-server*); do
    ${init} restart
done

# ======================================================================
# Create a Swift logical volume.
lvcreate -L 50G -n swift_shares blade_center
mke2fs -F -j /dev/blade_center/swift_shares
mkdir /swift
mount /dev/blade_center/swift_shares /swift

[ -f "/etc/rsyncd.conf" ] && cp /etc/rsyncd.conf /etc/rsyncd.conf.orig
cat <<EOF > /etc/rsyncd.conf
uid = swift
gid = swift
log file = /var/log/rsyncd.log
pid file = /var/run/rsyncd.pid
address = ${ip}
 
[account]
max connections = 2
path = /swift/
read only = false
lock file = /var/lock/account.lock
 
[container]
max connections = 2
path = /swift/
read only = false
lock file = /var/lock/container.lock
 
[object]
max connections = 2
path = /swift/
read only = false
lock file = /var/lock/object.lock
EOF

# ======================================================================
# Install the ZFS/ZoL Openstack Cinder plugin.
curl -s http://${LOCALSERVER}/PXEBoot/install_cinder_zfs.sh > \
    /var/tmp/install_cinder_zfs.sh
sh -x /var/tmp/install_cinder_zfs.sh

# ======================================================================
# Import a bunch of external images.
# NOTE: Need to run this with nohup in the background, because this will
#       take a while!
curl -s http://${LOCALSERVER}/PXEBoot/install_images.sh > \
    /var/tmp/install_images.sh
echo "Running /var/tmp/install_images.sh in the background."
nohup sh -x /var/tmp/install_images.sh > \
    /var/tmp/install_images.log 2>&1 &

# ======================================================================
# Save our config file state.
find /etc -name '*.orig' | \
    while read file; do
	f="$(echo "${file}" | sed 's@\.orig@@')"
        cp "${f}" "${f}.save0" # Initial install states
        cp "${f}" "${f}.save"
done
