#!/bin/bash

DEHYDRATED="/usr/local/bin/dehydrated"
CALL="$DEHYDRATED -c"

RESULT=$($CALL)
RETURN=$?

if [ "0${RETURN}" -ne "0" ]; then
    echo "$CALL exited with ${RETURN}"
    echo
    echo "$RESULT"
fi

if [ ! -z "$1" ]; then
    LTRG=$1
    LEN=$(echo "$RESULT" | wc -l)
    if [ $LEN -gt $LTRG ]; then
        echo "$RESULT"
    fi
fi
