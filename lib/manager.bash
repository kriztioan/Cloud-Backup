#!/bin/bash

function manager_init {

    if [ ! -e "$SUPPORT_FOLDER/share/$MANAGER_FILE" ]
    then

	manager_create

	return
    fi

    return 0
}

function manager_create {

    /usr/local/bin/dar_manager -C "$SUPPORT_FOLDER/share/$MANAGER_FILE"
}

function manager_add {

    /usr/local/bin/dar_manager -ai -B "$SUPPORT_FOLDER/share/$MANAGER_FILE" -A "$1" "$2"
}

function manager_restore {

    /usr/local/bin/dar_manager -B "$SUPPORT_FOLDER/share/$MANAGER_FILE" -ai -Q --ignore-when-removed -e "$1" -r "${@:2}"
}

function manager_trim {

  while true; do

    LIST=$( /usr/local/bin/dar_manager -B "$SUPPORT_FOLDER/share/$MANAGER_FILE" --list )

    LEVELS=( $( echo "$LIST" | /usr/bin/grep "$1" | /usr/bin/awk '{print $3}' | /usr/bin/sed -E "s|$1\.(.*)|\1|" ) )

    if [ "${LEVELS[${#LEVELS[@]}-1]}" -le "$2" ]
    then

      break
    fi

    NUMBERS=( $( echo "$LIST" | /usr/bin/grep "$1" | /usr/bin/awk '{print $1}' ) )

    /usr/local/bin/dar_manager -B "$SUPPORT_FOLDER/share/$MANAGER_FILE" --delete ${NUMBERS[${#NUMBERS[@]}-1]}
  done
}
