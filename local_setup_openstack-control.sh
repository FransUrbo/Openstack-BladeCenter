#!/bin/sh

set -xe

if [ ! -e /usr/share/openstack-pkg-tools/pkgos_func ]; then
    echo "ERROR: openstack-pkg-tools not installed"
    exit 1
else
    . /usr/share/openstack-pkg-tools/pkgos_func
    export PKGOS_VERBOSE=yes
fi

if [ ! -e "admin-openrc" ]; then
    echo "The admin-openrc file don't exists."
    exit 1
else
    set +x # Disable showing commands this do (password especially).
    . /root/admin-openrc
fi

set -x

# Get IP of this host
set -- $(/sbin/ip address | egrep " eth1.* UP ")
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
    # Just tripple check.
    curl -s http://${LOCALSERVER}/PXEBoot/debconf_openstack-control.txt | \
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

# Configure Manila.
pkgos_inifile set /etc/manila/manila.conf DEFAULT driver_handles_share_servers True
pkgos_inifile set /etc/manila/manila.conf DEFAULT service_instance_user True
pkgos_inifile set /etc/manila/manila.conf DEFAULT storage_availability_zone nova
for init in /etc/init.d/manila-*; do $init restart; done

# Configure Nova.
pkgos_inifile set /etc/nova/nova.conf DEFAULT dmz_net 10.99.0.0
pkgos_inifile set /etc/nova/nova.conf DEFAULT dmz_mask 255.255.255.0
pkgos_inifile set /etc/nova/nova.conf DEFAULT pybasedir /usr/lib/python2.7/dist-packages
pkgos_inifile set /etc/nova/nova.conf DEFAULT enabled_apis osapi_compute,metadata
pkgos_inifile set /etc/nova/nova.conf DEFAULT use_neutron True
pkgos_inifile set /etc/nova/nova.conf DEFAULT memcached_servers 127.0.0.1:11211
pkgos_inifile set /etc/nova/nova.conf DEFAULT internal_service_availability_zone internal
pkgos_inifile set /etc/nova/nova.conf DEFAULT default_availability_zone nova
pkgos_inifile set /etc/nova/nova.conf DEFAULT default_schedule_zone nova
pkgos_inifile set /etc/nova/nova.conf DEFAULT block_device_allocate_retries 300
pkgos_inifile set /etc/nova/nova.conf DEFAULT block_device_allocate_retries_interval 10
pkgos_inifile set /etc/nova/nova.conf DEFAULT block_device_creation_timeout 300
pkgos_inifile set /etc/nova/nova.conf DEFAULT scheduler_default_filters RetryFilter,AvailabilityZoneFilter,RamFilter,DiskFilter,ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ServerGroupAntiAffinityFilter,ServerGroupAffinityFilter
pkgos_inifile set /etc/nova/nova.conf DEFAULT baremetal_scheduler_default_filters RetryFilter,AvailabilityZoneFilter,ComputeFilter,ComputeCapabilitiesFilter,ImagePropertiesFilter,ExactRamFilter,ExactDiskFilter,ExactCoreFilter
pkgos_inifile set /etc/nova/nova.conf DEFAULT my_block_storage_ip \$my_ip
pkgos_inifile set /etc/nova/nova.conf DEFAULT routing_source_ip \$my_ip
pkgos_inifile set /etc/nova/nova.conf DEFAULT metadata_host \$my_ip
pkgos_inifile set /etc/nova/nova.conf cinder cross_az_attach True
pkgos_inifile set /etc/nova/nova.conf neutron url "http://${ctrlnode}:9696/"
for init in /etc/init.d/nova-*; do $init restart; done

# Configure Zaqar.
pkgos_inifile set /etc/zaqar/zaqar.conf "drivers:management_store:mongodb" database zaqar
pkgos_inifile set /etc/zaqar/zaqar.conf keystone_authtoken memcached_servers 127.0.0.1:11211
pkgos_inifile set /etc/zaqar/zaqar.conf DEFAULT unreliable True
pkgos_inifile set /etc/zaqar/zaqar.conf drivers:transport:wsgi bind "${ip}"
/etc/init.d/zaqar-server restart

# Configure Cinder.
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT my_ip "${ip}"
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT volume_group blade_center
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT storage_availability_zone nova
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT default_availability_zone nova
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT scheduler_driver cinder.scheduler.filter_scheduler.FilterScheduler
# TODO: Not yet.
#pkgos_inifile set /etc/cinder/cinder.conf DEFAULT nas_ip 192.168.69.8
#pkgos_inifile set /etc/cinder/cinder.conf DEFAULT nas_login root
#pkgos_inifile set /etc/cinder/cinder.conf DEFAULT nas_private_key /etc/cinder/sshkey
#pkgos_inifile set /etc/cinder/cinder.conf DEFAULT nas_share_path share/Blade_Center
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT iscsi_target_prefix iqn.2010-10.org.openstack:
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT iscsi_port 3260
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT iscsi_iotype blockio
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT iscsi_write_cache on
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT iscsi_ip_address \$my_ip
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT volume_name_template '%s'
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT snapshot_name_template '%s.snap'
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT backup_name_template '%s.back'
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT iscsi_helper tgtadm
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT iscsi_protocol iscsi
pkgos_inifile set /etc/cinder/cinder.conf DEFAULT volume_dd_blocksize 4M
pkgos_inifile set /etc/cinder/cinder.conf keystone_authtoken memcached_servers 127.0.0.1:11211
pkgos_inifile set /etc/cinder/cinder.conf lvm volume_group blade_center
for init in /etc/init.d/cinder-*; do $init restart; done

# Configure Neutron.
pkgos_inifile set /etc/neutron/neutron.conf DEFAULT default_availability_zones nova
pkgos_inifile set /etc/neutron/neutron.conf DEFAULT availability_zone nova
pkgos_inifile set /etc/neutron/dhcp_agent.ini DEFAULT force_metadata True
pkgos_inifile set /etc/neutron/dhcp_agent.ini DEFAULT enable_metadata_network True
pkgos_inifile set /etc/neutron/dhcp_agent.ini DEFAULT dnsmasq_dns_servers 10.0.0.254
pkgos_inifile set /etc/neutron/dhcp_agent.ini DEFAULT enable_isolated_metadata True
pkgos_inifile set /etc/neutron/l3_agent.ini DEFAULT rpc_workers 5
pkgos_inifile set /etc/neutron/l3_agent.ini DEFAULT rpc_state_report_workers 5
pkgos_inifile set /etc/neutron/plugins/ml2/ml2_conf.ini securitygroup firewall_driver iptables_hybrid
pkgos_inifile get /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers 
[ -n "${RET}" ] && RET="${RET},"
pkgos_inifile set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 type_drivers "${RET}vlan"
pkgos_inifile set /etc/neutron/plugins/ml2/ml2_conf.ini ml2 extension_drivers port_security
pkgos_inifile get /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks
[ -n "${RET}" ] && RET="${RET},"
pkgos_inifile set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_flat flat_networks "${RET}provider"
pkgos_inifile set /etc/neutron/plugins/ml2/ml2_conf.ini ml2_type_vlan network_vlan_ranges provider
#pkgos_inifile set /etc/neutron/neutron_lbaas.conf service_providers service_provider LOADBALANCERV2:Haproxy:neutron_lbaas.drivers.haproxy.plugin_driver.HaproxyOnHostPluginDriver:default
pkgos_inifile set /etc/neutron/neutron_lbaas.conf service_auth auth_url "http://${ctrlnode}:35357/v2.0"
pkgos_inifile set /etc/neutron/neutron_lbaas.conf service_auth admin_username admi
pkgos_inifile set /etc/neutron/neutron_lbaas.conf service_auth admin_password "${neutron_pass}"
pkgos_inifile set /etc/neutron/neutron_lbaas.conf service_auth region europe-london
#pkgos_inifile set /etc/neutron/neutron_lbaas.conf DEFAULT interface_driver openvswitch # Needs to be done manually
#if [ "${RET}" != "NO_VALUE" ]; then
#    [ -n "${RET}" ] && RET="${RET},"
#    pkgos_inifile set /etc/neutron/neutron.conf DEFAULT service_plugins "${RET}???"
#fi
for init in /etc/init.d/neutron-*; do $init restart; done

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

# ======================================================================
# Create some security groups.

# Create the new security groups.
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

# ======================================================================
# Create some key pairs.
curl -s http://${LOCALSERVER}/PXEBoot/id_rsa.pub > /var/tmp/id_rsa.pub
openstack keypair create --public-key /var/tmp/id_rsa.pub "Turbo Fredriksson"
rm /var/tmp/id_rsa.pub

# ======================================================================
# Update the default quota.
openstack quota set --key-pairs 2 --fixed-ips 2 --floating-ips 2 \
    --volumes 10 --snapshots 10 --ram 512 --injected-files 10 \
    --gigabytes 100 --secgroups 20 --secgroup-rules 5 default

# ======================================================================
# Create some host aggregates. Might be nice to have. Eventually.
openstack aggregate create --zone nova infra
openstack aggregate create --zone nova devel
openstack aggregate create --zone nova build
openstack aggregate create --zone nova tests

# ======================================================================
# Create some volume types
openstack volume type create --description "Encrypted volume" --public encrypted
cinder encryption-type-create --cipher aes-xts-plain64 --key_size 512 \
    --control_location front-end encrypted LuksEncryptor
openstack volume type create --description "Local LVM volume" --public local
openstack volume type create --description "Remote ZFS volume" --public remote
# TODO: !! Create extra spec key-value pairs for these !!

# ======================================================================
# Setup Open vSwitch
ovs-vsctl add-br br-physical
#ovs-vsctl add-port br-physical eth1 # TODO: !! This will cut traffic on eth1 !!
ovs-vsctl add-br br-provider
ovs-vsctl add-port br-provider eth0
pkgos_inifile set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs bridge_mappings provider:br-provider
pkgos_inifile set /etc/neutron/plugins/ml2/openvswitch_agent.ini ovs local_ip "${ip}"
for init in /etc/init.d/*openvswitch*; do $init restart; done

# ======================================================================
# Create network(s), routers etc.
# TODO: !! I really need to understand Neutron networking first !!

# Setup the physical network
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

exit 0

#neutron router-gateway-set --fixed-ip subnet_id=subnet-physical,ip_address=10.0.0.200 \
#    router-physical physical
