#!/bin/bash

## Sort photos to respective folder
#
# Author: Stefan Haun <tux@netz39.de>


EXIF_TOOL=exiftool

# Includes (see http://stackoverflow.com/a/12694189)
DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$DIR" ]]; then DIR="$PWD"; fi

source "$DIR/journal_config.sh"
source "$DIR/journal_util.sh"


# Extract the exif date from an image
function extract_exif_date() {
    local FILEPATH=$1
    
    local TAG_CD=$($EXIF_TOOL -s -s -s -CreateDate -d "%F" -t "$FILEPATH")
    
    echo $TAG_CD
}

IMGPATH="/home/tux/tmp/Camera/Cam1/IMG_20150711_153705.jpg"


TAG_CD=$(extract_exif_date $IMGPATH)

DIR=$(render_target_dir "$JOURNAL_PREFIX" $TAG_CD)
echo $DIR

mkdir -p $DIR

cp "$IMGPATH" "$DIR"
