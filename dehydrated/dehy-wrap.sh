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

