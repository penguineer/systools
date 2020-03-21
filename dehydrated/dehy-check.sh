#!/bin/bash

BASEDIR=/usr/local/etc/dehydrated
SPAN=864000

check_certs() {
    for pem in $BASEDIR/certs/*/cert.pem; do

        RET=$(openssl x509 -checkend $SPAN -noout -in $pem)
        RETURN=$?

        if [ "0${RETURN}" -ne "0" ]; then
            printf '%s: %s\n' \
                "$(date --date="$(openssl x509 -enddate -noout -in "$pem"|cut -d= -f 2)" --iso-8601)" \
                "$pem"
        fi
    done | sort
}

issues="$(check_certs)"

if [ ! -z "$issues" ]; then
    echo "Some certs will expire soon. Check dehydrated calls!"
    echo
    echo "$issues"
fi
