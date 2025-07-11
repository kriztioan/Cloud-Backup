#!/bin/bash
###
#  @file   cloud_trim.bash
#  @brief  Trim Backup
#  @author KrizTioaN (christiaanboersma@hotmail.com)
#  @date   2022-05-20
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

# Source manager

source "$SUPPORT_FOLDER/lib/manager.bash"

function trim {

  # Check for target

  message "checking target"

  /usr/local/bin/rclone about "$TARGET" $RCLONE_OPTS >/dev/null 2>&1

  if [ ! $? -eq 0 ]; then

    message "target ($TARGET) not available"

    return 1
  fi

  # Trim manager

  message "trimming manager"

  manager_trim "$BACKUP_NAME" "$TRIM_LEVEL"

  # Getting last update

  message "purging backups"

  db_last "$BACKUP_NAME"

  if [ $? -eq 0 ]; then

    NLEVEL=$(($LEVEL - $TRIM_LEVEL))

    message 0%

    L=$LEVEL

    until [[ "$L" -le "$TRIM_LEVEL" ]]; do

      /usr/local/bin/rclone --include "$BACKUP_NAME.$L.*" delete "$TARGET" $RCLONE_OPTS

      L=$(($L - 1))

      PERC=$((100 - 100 * ($L - $TRIM_LEVEL) / $NLEVEL))

      message $PERC%
    done

    message 100%
  fi

  # Trim database

  message "trimming database"

  db_trim "$BACKUP_NAME" "$TRIM_LEVEL"

  return 0
}

function main {

  # Starting

  TIMESTAMP=$(date +"%s")

  message "start trimming cloud backup (PID $$)"

  # Unload the launch agent

  AGENT=$(launchctl list "$PERIODIC_LAUNCH_AGENT" >/dev/null 2>/dev/null)

  AGENT_ACTIVE=$?

  if [ "$AGENT_ACTIVE" -eq "0" ]; then

    launchctl unload "$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist"

    message "unloaded $PERIODIC_LAUNCH_AGENT"
  fi

  # Check for lock file

  if [ -e "$SUPPORT_FOLDER/var/$LOCK_FILE" ]; then

    message "lock file found at $SUPPORT_FOLDER/var/$LOCK_FILE"

    PID=$(cat "$SUPPORT_FOLDER/var/$LOCK_FILE")

    message "a cloud backup is running with pid $PID... terminating"

    exit 0
  fi

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

  RAM_DEV=$(hdiutil attach -agent hdid -nomount ram://$((15 * 2 * (2 * $DAR_BYTES / 1024) / 10)))

  if [ "$?" -ne 0 ]; then

    message "unable to create workspace... terminating"

    exit 0
  fi

  newfs_hfs $RAM_DEV >/dev/null

  mount -o nobrowse -o noatime -t hfs ${RAM_DEV} ${WORKSPACE}

  CWD=$(pwd -P)

  cd "$WORKSPACE"

  message "workspace created at $WORKSPACE"

  # Write lock file

  echo $$ >"$SUPPORT_FOLDER/var/$LOCK_FILE"

  message "lock file written at $SUPPORT_FOLDER/var/$LOCK_FILE"

  # Set trim level

  TRIM_LEVEL="$2"

  # Loop over sources

  if [ $# -gt 0 ]; then

    source "$SUPPORT_FOLDER"/etc/config.d/"$1"

    message "trimming $BACKUP_NAME to level $TRIM_LEVEL"

    trim

    if [ $? -ne 0 ]; then

      message "trimming $BACKUP_NAME failed... terminating"

      exit 0
    fi

    message "completed trimming $BACKUP_NAME"
  else

    for CONFIG in "$SUPPORT_FOLDER"/etc/config.d/*; do

      source "$CONFIG"

      message "trimming $BACKUP_NAME to level $TRIM_LEVEL"

      trim

      if [ $? -ne 0 ]; then

        message "trimming $BACKUP_NAME failed... terminating"

        exit 0
      fi

      message "completed trimming $BACKUP_NAME"
    done
  fi

  # Save database

  /usr/local/bin/rclone copy "$SUPPORT_FOLDER/share/$DB_FILE" "$TARGET" $RCLONE_OPTS

  message "database saved"

  # Save manager

  /usr/local/bin/rclone copy "$SUPPORT_FOLDER/share/$MANAGER_FILE" "$TARGET" $RCLONE_OPTS

  message "manager saved"

  # Cleanup

  cleanup

  # Load launch agent

  if [ "$AGENT_ACTIVE" -eq "0" ]; then

    launchctl load "$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist"

    message "loaded $PERIODIC_LAUNCH_AGENT"
  fi

  # Done

  ELAPSED=$(($(date "+%s") - $TIMESTAMP))

  DELTA=$(printf "%03d:%02d:%02d" $(($ELAPSED / 3600)) $((($ELAPSED % 3600) / 60)) $(($ELAPSED % 3600 % 60)))

  message "completed trimming cloud backup in $DELTA"
}

main "$@" >>"$HOME/Library/Logs/$LOG_FILE" 2>&1
