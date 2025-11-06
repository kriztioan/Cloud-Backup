#!/bin/bash
###
#  @file   cloud_restore_file.bash
#  @brief  Restore File from Cloud Backup
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

function restore {

  # Check for argument

  if [ "$#" -lt 1 ]; then

    return 1
  fi

  # Check for target

  message "checking target"

  rclone about "$TARGET" $RCLONE_OPTS >/dev/null 2>&1

  if [ ! $? -eq 0 ]; then

    message "target ($TARGET) not available... terminating"

    return 2
  fi

  db_last "$BACKUP_NAME"

  if [ $? -ne 0 ]; then

    message "no backups found... terminating"

    return 3
  fi

  message "checking destination"

  if [ ! -d "$DESTINATION" ]; then

    message "destination ($DESTINATION) does not exist... creating"

    mkdir "$DESTINATION"
  fi

  # Restore

  message "dar_manager started"

  message "restoring backup of '$@'"

  touch prev_basename

  manager_restore "-q -9 6 -O -w -Q -al \
    -R '$DESTINATION' \
    -E \"'$DAR_SCRIPT' restore %b $TARGET %n %b\"" \
    "$@"

  DAR_CODE=$?

  message "dar_manager finished with code $DAR_CODE"

  rm -f prev_basename

  return $DAR_CODE
}

function main {

  # Starting

  message "starting file restore from the Cloud (PID $$)"

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

  CWD=$(pwd -P)

  cd "$WORKSPACE"

  message "workspace created at $WORKSPACE"

  # Restore file

  source "$SUPPORT_FOLDER"/etc/config.d/"$1"

  message "Doing $BACKUP_NAME"

  restore "${@:2}"

  if [ $? -ne 0 ]; then

    message "Restore failed"
  else

    message "Completed $BACKUP_NAME"
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

  message "restored file from the Cloud in $DELTA"
}

main "$@"
