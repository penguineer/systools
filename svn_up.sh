#!/bin/bash

SVN_FIND="$HOME/bin/systools/svn_find.sh"

COLOR_WIPE="\033[0m"
COLOR_WHITE="\033[1;37m"
COLOR_GREEN="\033[0;32m"
COLOR_RED="\033[1;31m"

function error_exit
{
	echo -e "$COLOR_RED${PROGNAME}: ${1:-"Unknown Error"}$COLOR_WIPE" 1>&2
	exit 1
}


echo "Locating SVN working copies …"
if [[ -x "$SVN_FIND" ]] ; then
  WC=$( $SVN_FIND $HOME | grep -v -E $HOME/eclipse | grep -v -E $HOME/Backup/)
else
  error_exit "Could not find svn_find script!"
fi

FAILS=""

for p in $WC ; do
  echo -e "$COLOR_WHITE> Updating $p$COLOR_WIPE"
  ERROR=$(svn up $p 3>&1 1>&2 2>&3 | tee >(cat - >&2))
  if [ -n "$ERROR" ]; then
    #Add to failure log
    FAILS="$FAILS$p\n"
    echo -e "${COLOR_RED}Failed!$COLOR_WIPE";
  else
    echo -e "${COLOR_GREEN}OK$COLOR_WIPE";
  fi
  echo
done


if [ -n "$FAILS" ]; then
  echo -e "${COLOR_RED}Failed repositories:"
  echo -e "$FAILS$COLOR_WIPE"
else
  echo -e "${COLOR_GREEN}Done without errors.$COLOR_WIPE"
fi

