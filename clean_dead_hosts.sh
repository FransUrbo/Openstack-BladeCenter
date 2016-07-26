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

#set -xe

# ======================================================================
# Remove the compute nodes no longer available.
echo "Services: "
nova-manage service list 2> /dev/null | \
    grep -v ^Binary | \
    grep 'XXX' | \
    while read line; do
	set -- $(echo "${line}")
        [ "${2}" = "0.0.0.0" ] && continue

        nova-manage service disable --host="${2}" \
            --service="${1}" 2> /dev/null
done
mysql --defaults-file=/etc/mysql/debian.cnf nova \
    -e "delete from services where host not like '0.0.0.0' and disabled=1"
echo

# ======================================================================
# Remove hypervisors no longer available.
echo "Hypervisors: "
openstack hypervisor list | \
    egrep -v '^\+|ID' | \
    while read line; do
        set -- $(echo "${line}")

        if ! openstack hypervisor show "${4}" > /dev/null 2>&1
        then
            mysql --defaults-file=/etc/mysql/debian.cnf -B nova \
                  -e "delete from compute_nodes where hypervisor_hostname='${4}'"
        fi
    done
echo

# ======================================================================
# Remove agents no longer available.
echo "Agents: "
neutron agent-list -c id -c host -c alive | \
    grep ' xxx ' | \
    while read line; do
	set -- $(echo "${line}")

	neutron agent-delete "${2}"
    done
