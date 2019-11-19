#!/bin/bash
#
# Manage GnuCash accounting repository around loading GnuCash
#
# Author: Stefan Haun (tux@netz39.de)
# SPDX-License-Identifier: MIT

# Check directory (Booking Dir must be present)

if [ ! -d "Booking" ]; then
    echo "Booking directory not present!"
    exit 1
fi

git pull

# Make sure the pull was successfull,
# otherwise we might work with an old state
if [ $? -ne 0 ]; then
    echo "Git pull failed!"
    echo "Exiting to avoid inconsistencies."
    exit 2
fi

# turn numlock on
if [ -x /usr/bin/numlockx ]; then
      /usr/bin/numlockx on
fi

GTK_THEME=Breeze:light LANG=de_DE.UTF-8 gnucash Booking/GnuCash_Tux.gnucash

# try to add these anyways, so further untracked files can be ignored
git add Booking/*

if [ ! -z "$(git status --untracked-files=no --porcelain)" ]; then
    echo "Pushing additions and changes"

    DATE=$(date "+%F %R")

    git commit -a -m "Stand $DATE"
    git push
else
    echo "No changes tracked."
fi
