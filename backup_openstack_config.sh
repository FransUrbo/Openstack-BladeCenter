#!/bin/sh

OPTS="${*}"

DATE="$(date +"%Y%m%d_%H%M")"

echo "Backing up Openstack databases at ${DATE}:"
find /etc -name '*.orig' -o -name '*~' | \
    sed -e 's@\.orig@@' -e 's@~@@' | \
    sort | uniq | \
    while read file; do
	echo "${file}" | \
            egrep -q "network/interfaces|\.lock" && \
            continue

        echo "${file}"

	dir="/tmp/openstack.$$/$(dirname "${file}")"
        mkdir -p "${dir}"

        grep '^[a-z\[]' "${file}" > "${dir}/$(basename "${file}")"
    done

cd /tmp/openstack.$$
tar czf /var/backups/openstack-configs-${DATE}.tar.gz \
    $(find -type f | sort)

echo "${OPTS}" | grep -q "no-clean" || \
    rm -Rf /tmp/openstack.$$
