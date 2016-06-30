#!/bin/sh                                                                                                                                                     

if ! /usr/sbin/rabbitmqctl -t 10 list_users > /dev/null 2>&1 ; then
    echo "Can't connect. Just make sure it's not actually running."
    cnt="$(/bin/ps faxwww | grep rabbitmq-server | grep -v grep | wc -l)"
    [ "${cnt}" -eq 2 ] || /etc/init.d/rabbitmq-server stop

    echo "Not running, restarting."
    /etc/init.d/rabbitmq-server start
fi
