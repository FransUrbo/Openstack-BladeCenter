#!/bin/sh

get_debconf_value () {
    debconf-get-selections | \
        egrep "^${1}[ $(printf '\t')].*${2}[ $(printf '\t')]" | \
        sed 's@.*[ \t]@@'
}

mysql_root_pass="$(get_debconf_value "dbconfig-common" "/mysql/admin-pass")"
mysql -uroot -p${mysql_root_pass} -hopenstack.bayour.com -Dmysql \
    -e "SET GLOBAL max_connections = 5000"
