#!/bin/sh

DATE="$(date +"%Y%m%d_%H%M")"

echo "Backing up Openstack databases at ${DATE}:"
mysql --defaults-file=/etc/mysql/debian.cnf -B -e "show databases" | \
    egrep -v '^Database|^information_schema|^mysql|^performance_schema' | \
    while read database; do
	echo -n "  ${database}: "
	mysqldump --defaults-file=/etc/mysql/debian.cnf --add-drop-table \
            --add-drop-trigger --add-locks --complete-insert --compress \
            "${database}" | \
            gzip -9 > "/var/backups/openstack-database-${database}-${DATE}.sql.gz"
        echo "done."
done
