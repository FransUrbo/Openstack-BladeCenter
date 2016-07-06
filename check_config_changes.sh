#!/bin/sh

find /etc -name '*.save' | \
    while read file; do
	f="${file%%.save}"
        diff -u "${file}" "${f}" > /tmp/$$
        [ "${?}" -ne "0" ] && cat /tmp/$$
    done
