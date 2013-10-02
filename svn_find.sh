#!/bin/bash

DIR=$1

#no argument?
if [ -z "$DIR" ]; then
  DIR=.
fi

find $DIR -type d -path '*\/\.svn' | \
  sed 's/\/\.svn.*\.*//' |\
  sort -u |\
  perl -lne's!/\.svn$!!i;$a&&/^$a/||print$a=$_'
