#!/bin/bash
###
#  @file   cloud_restore.bash
#  @brief  Restore Cloud Backups
#  @author KrizTioaN (christiaanboersma@hotmail.com)
#  @date   2021-07-24
#  @note   BSD-3 licensed
#
###############################################

# Support folder location

SUPPORT_FOLDER="$HOME/Library/Application Support/Cloud Backup"

# Source variables

source "$SUPPORT_FOLDER/etc/config"

# Source auxilary functions

source "$SUPPORT_FOLDER/lib/aux.bash"

# Source database

source "$SUPPORT_FOLDER/lib/db.bash"

function restore {

  # Check for target

  message "checking target"

  rclone ls "$TARGET" -q >/dev/null 2>&1

  if [ ! $? -eq 0 ]; then

    message "target ($TARGET) not available... terminating"

    return 1
  fi

  db_last "$BACKUP_NAME"

  if [ $? -ne 0 ]; then

    message "no backups found... terminating"

    return 2
  fi

  message "checking destination"

  if [ ! -d "$DESTINATION" ]; then

    message "destination ($DESTINATION) does not exist... creating"

    mkdir "$DESTINATION"
  fi

  message "last update (level-$LEVEL) dated $(date -r $DATE)"

  L=0

  until [ $L -gt $LEVEL ]; do

    # Retrieve slices

    rclone copy "$TARGET$BACKUP_NAME"."$L".slices . -q >/dev/null 2>&1

    NSLICES=$(cat "$BACKUP_NAME"."$L".slices)

    LAST_SLICE=$(printf "$BACKUP_NAME.$L.%06d.dar" "$NSLICES")

    echo -n 0 >wait_pid

    "$DAR_SCRIPT" catalogue "$LAST_SLICE" "$TARGET" "$NSLICES" "$BACKUP_NAME"."$L"

    # Restore

    message "dar started"

    message "restoring level-$L backup"

    /usr/local/bin/dar -x "$BACKUP_NAME"."$L" -q -9 6 -O -w -Q \
      -R "$DESTINATION" \
      -E "'$DAR_SCRIPT' extract %b.%N.dar $TARGET %n %b $NSLICES"

    DAR_CODE=$?

    message "dar finished with code $DAR_CODE"

    if [ $DAR_CODE -ne 0 ]; then

      message "please check the log file for any errors/warnings"
    fi

    rm -f "$LAST_SLICE"

    L=$(($L + 1))
  done

  return 0
}

function main {

  # Starting

  message "starting restore from the Cloud (PID $$)"

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

    message "Doing $BACKUP_NAME"

    restore

    if [ $? -ne 0 ]; then

      message "$BACKUP_NAME failed... terminating"

      abort 0
    fi

    message "Completed $BACKUP_NAME"
  else

    for CONFIG in "$SUPPORT_FOLDER"/etc/config.d/*; do

      source "$CONFIG"

      message "Doing $BACKUP_NAME"

      restore

      if [ $? -ne 0 ]; then

        message "$BACKUP_NAME failed... terminating"

        abort 0
      fi

      message "Completed $BACKUP_NAME"
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

  message "restored backup from the Cloud in $DELTA"
}

main "$@" 2>>"$HOME/Library/Logs/$LOG_FILE"
