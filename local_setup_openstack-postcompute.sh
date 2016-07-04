#!/bin/sh

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

set -xe

while ! openstack flavor list > /dev/null 2>&1; do
    echo "No flavors could be retrieved, sleeping 10 minutes"
    sleep "$(expr 60 \* 10)" # Sleep ten minutes, waiting for the first Compute.
done


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
clean_security_group default
neutron security-group-rule-create --direction ingress --protocol tcp --port-range-min 1 \
    --port-range-max 65535 --remote-ip-prefix 0.0.0.0/0 default
neutron security-group-rule-create --direction ingress --protocol udp --port-range-min 1 \
    --port-range-max 65535 --remote-ip-prefix 0.0.0.0/0 default
neutron security-group-rule-create --direction egress  --protocol tcp --port-range-min 1 \
    --port-range-max 65535 --remote-ip-prefix 0.0.0.0/0 default
neutron security-group-rule-create --direction egress  --protocol udp --port-range-min 1 \
    --port-range-max 65535 --remote-ip-prefix 0.0.0.0/0 default
neutron security-group-rule-create --direction ingress --protocol icmp --remote-ip-prefix \
    0.0.0.0/0 default
neutron security-group-rule-create --direction egress  --protocol icmp --remote-ip-prefix \
    0.0.0.0/0 default

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
    --port-range-max 389 --remote-ip-prefix 0.0.0.0/0 ldap
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
# Create a bunch (20) of floating IPs.
i=0
while [ "${i}" -le 19 ]; do
    openstack ip floating create physical
    i="$(expr "${i}" + 1)"
done

