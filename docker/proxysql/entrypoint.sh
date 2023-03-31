#!/bin/sh
envsubst < /etc/proxysql.cnf.template > /etc/proxysql.cnf
exec proxysql -f -c /etc/proxysql.cnf --idle-threads -D /var/lib/proxysql
