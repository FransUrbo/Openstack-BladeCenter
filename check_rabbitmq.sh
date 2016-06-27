#!/bin/sh                                                                                                                                                     

if ! /usr/sbin/rabbitmqctl -t 10 list_users | grep -q openstack; then
    echo "Not running, restarting."
    /etc/init.d/rabbitmq-server start
fi
