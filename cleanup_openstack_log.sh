#!/bin/sh

egrep -v '.*POST /v2/.*/.*volume.* HTTP/1.1" status|cinder.volume.api.*Availability Zones retrieved successfully|nova.scheduler.host_manager.*Successfully synced instances from host|cinder.volume.api.*Volume info retrieved successfully|cinder.api.openstack.wsgi.*http://|manila.share.manager.*Updating share status|nova.scheduler.host_manager.*The instance sync for host.*did not match|designate.central.rpcapi.*find_zones: Calling central|GET /|HEAD /v1/images|ERROR designate.pool_manager.service.*No targets for|WARNING oslo_config.cfg.*Option "memcached_servers" from group "DEFAULT" is deprecated for removal|INFO designate.central.rpcapi.*get_pool: Calling|Policy check succeeded|^==|INFO heat.engine.service.*Service.*is updated|WARNING keystonemiddleware.auth_token.*Using the in-process token cache is deprecated|neutron.db.metering.metering_rpc.*Unable to find agent| _http_log_response |=INFO REPORT=|accepting AMQP connection|Connecting to AMQP server|Connected to AMQP server|Running periodic task|Logging enabled|neutron.common.config.*version |Synchronizing state|neutron.wsgi.*wsgi starting up on|Starting.*workers| IPv6 is not enabled on this system|DHCP agent.*is not active|agent started|agent.*is not active|Agent has just been revived|oslo_service.service.*packages/oslo_config/cfg.py:|^$' | \
    sed -e "s@^\(....-..-.. ..:..:..\.[0-9]\+ [0-9]\+ \)\(.*\)@\2@" \
        -e "s@\(.*\)\[.* - - -\]\(.*\)@\1\2@" \
        -e "s@\[.*\] @@" \
        -e "s@WARNING@WARN @" \
        -e "s@INFO @INFO  @"
