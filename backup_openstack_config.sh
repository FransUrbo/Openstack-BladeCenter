#!/bin/sh

rm -Rf /tmp/openstack
find /etc -name '*.orig' -o -name '*~' | \
    sed -e 's@\.orig@@' -e 's@~@@' | \
    sort | uniq | \
    while read file; do
	echo "${file}" | \
            egrep -q "network/interfaces" && \
            continue

        echo "${file}"

	dir="/tmp/openstack/$(dirname "${file}")"
        mkdir -p "${dir}"

        grep '^[a-z\[]' "${file}" > "${dir}/$(basename "${file}")"
    done
