#!/bin/bash
###
#  @file   cloud_manager.bash
#  @brief  Add Remote Catalogues to Manager
#  @author KrizTioaN (christiaanboersma@hotmail.com)
#  @date   2021-07-24
#  @note   BSD-3 licensed
#
###############################################

# Support folder location

SUPPORT_FOLDER="$HOME/Library/Application Support/Cloud Backup"

# Source variables

source "$SUPPORT_FOLDER/etc/config"

# Source auxiliary functions

source "$SUPPORT_FOLDER/lib/aux.bash"

# Source database

source "$SUPPORT_FOLDER/lib/db.bash"

# Source manager

source "$SUPPORT_FOLDER/lib/manager.bash"

function manage {

  # Check for target

  message "checking target"

  /usr/local/bin/rclone about "$TARGET" $RCLONE_OPTS >/dev/null 2>&1

  if [ ! $? -eq 0 ]; then

    message "target ($TARGET) not available... terminating"

    return 1
  fi

  message "target ($TARGET) is valid"

  db_last "$BACKUP_NAME"

  if [ $? -ne 0 ]; then

    message "no backups found... terminating"

    return 2
  fi

  LEVEL=$(($LEVEL + 1))

  L=0

  while [ $L -lt $LEVEL ]; do

    /usr/local/bin/rclone copy "$TARGET$BACKUP_NAME"."$L".catalogue.1.dar . $RCLONE_OPTS 2>/dev/null

    if [ ! $? -eq 0 ]; then

      message "no level-$L catalogue found... terminating"

      return 3
    fi

    message "retrieved level-$L catalogue"

    message "adding level-$L catalogue to manager"

    manager_add "$BACKUP_NAME"."$L".catalogue "$BACKUP_NAME"."$L"

    rm -f "$BACKUP_NAME"."$L".catalogue.1.dar

    L=$(($L + 1))
  done

  return 0
}

function main {

  # Starting

  message "starting manager from the Cloud (PID $$)"

  TIMESTAMP=$(date +"%s")

  # Unload the launch agent

  ACTIVE=$(launchctl list "$PERIODIC_LAUNCH_AGENT" >/dev/null 2>&1)

  SCHEDULED=$?

  if [ $SCHEDULED -eq "0" ]; then

    launchctl unload "$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist"

    message "unloaded $PERIODIC_LAUNCH_AGENT"
  fi

  # Check for lock file

  if [ -e "$SUPPORT_FOLDER/var/$LOCK_FILE" ]; then

    message "lock file found at $SUPPORT_FOLDER/var/$LOCK_FILE"

    PID=$(cat "$SUPPORT_FOLDER/var/$LOCK_FILE")

    message "cloud backup already running with pid $PID... terminating"

    return 2
  fi

  # Write lock file

  echo $$ >"$SUPPORT_FOLDER/var/$LOCK_FILE"

  message "lock file written at $SUPPORT_FOLDER/var/$LOCK_FILE"

  # Connect to data database

  db_connect

  if [ "$?" -ne 0 ]; then

    message "failed to connect to database... terminating"

    exit 0
  fi

  message "connected to database"

  # Init manager

  manager_init

  message "manager initialized"

  # Create work space

  message "creating workspace"

  WORKSPACE=$(mktemp -d -t cloud_backup)

  RAM_DEV=$(hdiutil attach -agent hdid -nomount ram://$((15 * 2 * (3 * $DAR_BYTES / 1024) / 10)))

  if [ "$?" -ne 0 ]; then

    message "unable to create workspace... terminating"

    exit 0
  fi

  newfs_hfs $RAM_DEV >/dev/null

  mount -o nobrowse -o noatime -t hfs ${RAM_DEV} ${WORKSPACE}

  CWD=$(pwd -P)

  cd "$WORKSPACE"

  message "workspace created at $WORKSPACE"

  # Loop over sources

  if [ $# -gt 0 ]; then

    source "$SUPPORT_FOLDER"/etc/config.d/"$1"

    message "doing $BACKUP_NAME"

    manage

    if [ $? -ne 0 ]; then

      message "$BACKUP_NAME failed... terminating"

      abort 0
    fi

    message "Completed $BACKUP_NAME"
  else

    for CONFIG in "$SUPPORT_FOLDER"/etc/config.d/*; do

      source "$CONFIG"

      message "Doing $BACKUP_NAME"

      manage

      if [ $? -ne 0 ]; then

        message "$BACKUP_NAME failed... terminating"

        abort 0
      fi

      message "completed $BACKUP_NAME"
    done
  fi

  # Cleanup

  cleanup

  # Load launch agents

  if [ $SCHEDULED -eq "0" ]; then

    launchctl load "$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist"

    message "loaded $PERIODIC_LAUNCH_AGENT"
  fi

  # Done

  ELAPSED=$(($(date "+%s") - $TIMESTAMP))

  DELTA=$(printf "%03d:%02d:%02d" $(($ELAPSED / 3600)) $((($ELAPSED % 3600) / 60)) $(($ELAPSED % 3600 % 60)))

  message "managed backup from the Cloud in $DELTA"
}

main "$@"
