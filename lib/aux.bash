#!/bin/bash
###
#  @file   aux.bash
#  @brief  Auxiliary Bash Functions
#  @author KrizTioaN (christiaanboersma@hotmail.com)
#  @date   2021-07-24
#  @note   BSD-3 licensed
#
###############################################

function message {
  /usr/local/bin/unbuffer echo "$(date "+%m-%d-%Y %H:%M:%S: $1")"
}

function human() {

  echo $1 | awk 'function human(x) {
                     s=" B   KiB MiB GiB TiB EiB PiB YiB ZiB"
                while (x>=1024 && length(s)>1)
                      {x/=1024; s=substr(s,5)}
                s=substr(s,1,4)
                xf=(s==" B  ")?"%5d   ":"%8.2f"
                return sprintf( xf"%s\n", x, s)
             }
             {gsub(/^[0-9]+/, human($1)); print}'
}

function cleanup {

  # Wait for things to finish

  sleep 5

  # Cleaning up work space

  message "cleaning up work space"

  cd "$CWD"

  if [ ! -z ${RAM_DEV+x} ]; then

      umount -f "$WORKSPACE"

      diskutil quiet eject $RAM_DEV
  fi

  rm -rf "$WORKSPACE"

  # Remove lock file

  rm "$SUPPORT_FOLDER/var/$LOCK_FILE"

  message "removed lock file at $SUPPORT_FOLDER/var/$LOCK_FILE"
}

function abort {

  cleanup

  exit "$1"
}
