#!/bin/bash
###
#  @file   cloud_level-0.bash
#  @brief  Perform Initial Backup
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

function backup {

  # Check for target

  message "checking target"

  /usr/local/bin/rclone about "$TARGET" $RCLONE_OPTS >/dev/null 2>&1

  if [ ! $? -eq 0 ]; then

    message "target ($TARGET) not available"

    return 1
  fi

  # Check for source

  message "checking source"

  if [ ! -d "$SOURCE" ]; then

    message "source ($SOURCE) not available"

    return 2
  fi

  # Getting last update

  db_last "$BACKUP_NAME"

  if [ $? -eq 0 ]; then

    message "last update (level-$LEVEL) dated $(date -r $DATE)"

    NLEVEL=$LEVEL

    message 0%

    L=$LEVEL

    until [[ $L -lt 0 ]]; do

      /usr/local/bin/rclone --include "$BACKUP_NAME.$L.*" delete "$TARGET" $RCLONE_OPTS

      PERC=$((100 - (100 * $L) / $NLEVEL)

      message $PERC%

      L=$(($L - 1))
    done

    message 100%
  fi

  # Do dar

  echo -n 0 >wait_pid

  message "dar started"

  message "doing a level-0 backup"

  caffeinate /usr/local/bin/dar -q -Q \
    -c "$BACKUP_NAME".0 \
    -s "$DAR_BYTES" \
    -R "$SOURCE" \
    -E "'$DAR_SCRIPT' create %b.%N.dar $TARGET %n $BACKUP_NAME.0" \
    --min-digits 6 \
    --on-fly-isolate "$BACKUP_NAME.0.catalogue" \
    --exclude .DS_Store \
    --prune .DocumentRevisions-V100 \
    --prune .TemporaryItems \
    --prune .Trashes

  DAR_CODE=$?

  if [ $DAR_CODE -ne 0 ]; then

    message "dar finished with code $DAR_CODE"

    message "please check the log file for any errors/warnings"
  fi

  WAIT_PID=$(cat wait_pid)

  if [ $WAIT_PID -ne 0 ]; then

    message "- wait on $(printf "$BACKUP_NAME.0.%06d.dar" $(cat "$BACKUP_NAME".0.slices))"

    while kill -0 "$WAIT_PID" 2>/dev/null; do

      sleep 0.5
    done
  fi

  BYTES=$(cat ./"$BACKUP_NAME".0.bytes)

  message "archived $(human $BYTES)"

  message "archiving level-0 catalogue"

  /usr/local/bin/rclone copy "$BACKUP_NAME".0.catalogue.1.dar "$TARGET" $RCLONE_OPTS

  # Archive slice(s)

  message "archiving slice(s)"

  /usr/local/bin/rclone copy "$BACKUP_NAME".0.slices "$TARGET" $RCLONE_OPTS

  # Commit to database

  message "committing to database"

  db_insert "$BACKUP_NAME" 0 $BYTES $(cat "$BACKUP_NAME".0.slices)

  # Add catalogue to manager

  message "adding catalogue to manager"

  manager_add "$BACKUP_NAME".0.catalogue "$BACKUP_NAME".0

  rm -f "$BACKUP_NAME".0.catalogue.1.dar

  return 0
}

function main {

  # Starting

  TIMESTAMP=$(date +"%s")

  message "starting level-0 cloud backup (PID $$)"

  # Unload the launch agent

  ACTIVE=$(launchctl list "$PERIODIC_LAUNCH_AGENT" >/dev/null 2>/dev/null)

  if [ $? -eq "0" ]; then

    launchctl unload "$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist"

    message "unloaded $PERIODIC_LAUNCH_AGENT"
  fi

  # Check for lock file

  if [ -e "$SUPPORT_FOLDER/var/$LOCK_FILE" ]; then

    message "lock file found at $SUPPORT_FOLDER/var/$LOCK_FILE"

    PID=$(cat "$SUPPORT_FOLDER/var/$LOCK_FILE")

    message "cloud backup already running with pid $PID... terminating"

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

  # Loop over sources

  if [ $# -gt 0 ]; then

    source "$SUPPORT_FOLDER"/etc/config.d/"$1"

    message "doing $BACKUP_NAME"

    backup

    if [ $? -ne 0 ]; then

      message "$BACKUP_NAME failed... terminating"

      abort 0
    fi

    message "completed $BACKUP_NAME"
  else

    for CONFIG in "$SUPPORT_FOLDER"/etc/config.d/*; do

      source "$CONFIG"

      message "Doing $BACKUP_NAME"

      backup

      if [ $? -ne 0 ]; then

        message "$BACKUP_NAME failed... terminating"

        abort 0
      fi

      message "completed $BACKUP_NAME"
    done
  fi

  # Save database

  /usr/local/bin/rclone copy "$SUPPORT_FOLDER/share/$DB_FILE" "$TARGET" $RCLONE_OPTS

  message "database saved"

  # Save manager

  /usr/local/bin/rclone copy "$SUPPORT_FOLDER/share/$MANAGER_FILE" "$TARGET" $RCLONE_OPTS

  message "manager saved"

  # Save timestamp

  date +"%s" >"$SUPPORT_FOLDER/var/$TIMESTAMP_FILE"

  /usr/local/bin/rclone copy "$SUPPORT_FOLDER/var/$TIMESTAMP_FILE" "$TARGET" $RCLONE_OPTS

  message "timestamp saved"

  # Cleanup

  cleanup

  # Write launch agent

  cat >"$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist" <<EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Minute</key>
       <integer>0</integer>
    <key>Hour</key>
    <integer>10</integer>
    <key>Day</key>
    <integer>$(date -v +${DAY_INTERVAL}d +"%d")</integer>
    <key>Month</key>
    <integer>$(date -v +${DAY_INTERVAL}d +"%m")</integer>
  </dict>
  <key>Label</key>
  <string>com.christiaanboersma.cloud_backup.periodic</string>
  <key>LowPriorityIO</key>
  <true/>
  <key>Nice</key>
  <integer>1</integer>
  <key>Program</key>
  <string>/bin/sh</string>
  <key>ProgramArguments</key>
  <array>
    <string>sh</string>
    <string>-c</string>
    <string>$HOME/Library/Application\ Support/Cloud\ Backup/bin/cloud_level-x.bash</string>
  </array>
</dict>
</plist>
EOL

  message "written $PERIODIC_LAUNCH_AGENT"

  # Load launch agent

  launchctl load "$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist"

  message "loaded $PERIODIC_LAUNCH_AGENT"

  message "level-1 backups scheduled to run at 10:00 AM on $(date -v +${DAY_INTERVAL}d +"%A, %B %e %Y")"

  # Done

  ELAPSED=$(($(date "+%s") - $TIMESTAMP))

  DELTA=$(printf "%03d:%02d:%02d" $(($ELAPSED / 3600)) $((($ELAPSED % 3600) / 60)) $(($ELAPSED % 3600 % 60)))

  message "completed level-0 cloud backup in $DELTA"
}

main "$@" >>"$HOME/Library/Logs/$LOG_FILE" 2>&1
