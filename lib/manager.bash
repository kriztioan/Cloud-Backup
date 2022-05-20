###
#  @file   manager.bash
#  @brief  DAR Manager Bash Functions
#  @author KrizTioaN (christiaanboersma@hotmail.com)
#  @date   2021-07-24
#  @note   BSD-3 licensed
#
###############################################

function manager_init {

  if [ ! -e "$SUPPORT_FOLDER/share/$MANAGER_FILE" ]; then

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

  STORE=$GREP_OPTIONS

  unset GREP_OPTIONS

  LIST=$(/usr/local/bin/dar_manager -B "$SUPPORT_FOLDER/share/$MANAGER_FILE" --list)

  LEVELS=($(echo "$LIST" | /usr/bin/grep "$1" | /usr/bin/awk '{print $3}' | /usr/bin/sed -E "s|$1\.(.*)|\1|"))

  NTRIM=$((${LEVELS[${#LEVELS[@]} - 1]} - $2))

  message 0%

  while [ "${LEVELS[${#LEVELS[@]} - 1]}" -gt "$2" ]; do

    NUMBERS=($(echo "$LIST" | /usr/bin/grep "$1" | /usr/bin/awk '{print $1}'))

    /usr/local/bin/dar_manager -B "$SUPPORT_FOLDER/share/$MANAGER_FILE" --delete ${NUMBERS[${#NUMBERS[@]} - 1]}

    LIST=$(/usr/local/bin/dar_manager -B "$SUPPORT_FOLDER/share/$MANAGER_FILE" --list)

    LEVELS=($(echo "$LIST" | /usr/bin/grep "$1" | /usr/bin/awk '{print $3}' | /usr/bin/sed -E "s|$1\.(.*)|\1|"))

    PERC=$((100 - 100 * (${LEVELS[${#LEVELS[@]} - 1]} - $2) / $NTRIM))

    message $PERC%
  done

  message 100%

  GREP_OPTIONS=$STORE
}
