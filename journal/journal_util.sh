#!/bin/bash

## Journal Utility functions
#
# Author: Stefan Haun <tux@netz39.de>

# Render a target directory based on prefix and date
#
# Param 1: directory prefix
# Param 2: a valid date string
# Returns 0 if everything worked out, 1 if there is an error. 
#         The result directory is printed to stdout
#         The error message has been sent to stdout
function render_target_dir() {
    local PREFIX=${1%/}
    local DATESTR="$2"
    
    local ISODATE=$(date -d "$DATESTR" "+%F")
    
    if [ "$?" != "0" ]; then
        echo $ISODATE
        return 1
    fi
    
    local DIR="$PREFIX/$ISODATE"
    
    echo $DIR
    return 0
}
export -f render_target_dir
