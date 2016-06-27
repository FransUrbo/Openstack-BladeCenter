#!/bin/sh

curl -s -i -H "Content-Type: application/json" -d '
{ "auth": {
    "identity": {
      "methods": ["password"],
      "password": {
        "user": {
          "name": "admin",
          "domain": { "id": "default" },
          "password": "secret39"
        }
      }
    }
  }
}' http://openstack.domain.tld:5000/v3/auth/tokens | \
    grep '^\{' | python -mjson.tool
echo ; echo

curl -s -i -H "Content-Type: application/json" -d '
{ "auth": {
    "identity": {
      "methods": ["password"],
      "password": {
        "user": {
          "name": "admin",
          "domain": { "id": "default" },
          "password": "secret39"
        }
      }
    },
    "scope": {
      "project": {
        "name": "admin",
        "domain": { "id": "default" }
      }
    }
  }
}' http://openstack.domain.tld:5000/v3/auth/tokens | \
    grep '^\{' | python -mjson.tool
echo ; echo

curl -s -i -H "Content-Type: application/json" -d '
{ "auth": {
    "identity": {
      "methods": ["password"],
      "password": {
        "user": {
          "name": "admin",
          "domain": { "id": "default" },
          "password": "secret39"
        }
      }
    },
    "scope": {
      "domain": {
        "id": "default"
      }
    }
  }
}' http://openstack.domain.tld:5000/v3/auth/tokens | \
    grep '^\{' | python -mjson.tool
echo ; echo
