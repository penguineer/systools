#!/bin/bash
#
# Environment:
# APT_PROXY_PORT set proxy port, defaults to 3142
# HOST_IP set the cache IP, defaults to 'apt-proxy'
#
# See https://wiki.debian.org/AptCacherNg#Clients for details on
# return values

if [ -z $APT_PROXY_PORT ] ; then
  export APT_PROXY_PORT=3142
fi
if [ -z "${HOST_IP}" ]; then
  export HOST_IP="apt-proxy"
fi

timeout 1 bash -c 'cat < /dev/null > /dev/tcp/${HOST_IP}/${APT_PROXY_PORT}' 2> /dev/null
if [ $? -eq 0 ]; then
    echo "${HOST_IP}:${APT_PROXY_PORT}"
else
    echo "DIRECT"
fi