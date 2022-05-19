#!/bin/bash

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

    /usr/local/bin/rclone ls "$TARGET" $RCLONE_OPTS > /dev/null 2>&1

    if [ ! $? -eq 0 ]
    then

      message "target ($TARGET) not available"

      return 1
    fi

    # Trim database

    db_trim "$BACKUP_NAME" "$TRIM_LEVEL"

    # Trim manager
    manager_trim "$BACKUP_NAME" "$TRIM_LEVEL"

    # Getting last update

    db_last "$BACKUP_NAME"

    if [ $? -eq 0 ]
    then

      message "purging $(( $LEVEL-$TRIM_LEVEL )) level(s)"

      L=$LEVEL

      until [[ "$L" -le "$TRIM_LEVEL" ]]; do

        SLICE=1

        until [[ $SLICE -gt $SLICES ]]; do

          ARCHIVE=$( printf "$BACKUP_NAME.$L.%06d.dar" $SLICE )

          /usr/local/bin/rclone delete "$TARGET$ARCHIVE" $RCLONE_OPTS

          /usr/local/bin/rclone delete "$TARGET$ARCHIVE.par2" $RCLONE_OPTS

          /usr/local/bin/rclone --include "$ARCHIVE.vol*+*.par2" delete "$TARGET" $RCLONE_OPTS

          SLICE=$(( $SLICE + 1 ))
        done

        /usr/local/bin/rclone delete "$TARGET$BACKUP_NAME"."$L".slices $RCLONE_OPTS

        if [[ $SLICES -gt 0 ]]
        then

          /usr/local/bin/rclone delete "$TARGET$BACKUP_NAME"."$L".catalogue.1.dar $RCLONE_OPTS
        fi

        L=$(( $L - 1 ))
      done
    fi

    return 0
}

function main {

    # Starting

    TIMESTAMP=$( date +"%s" )

    message "start trimming cloud backup (PID $$)"

    # Unload the launch agent

    AGENT=$(launchctl list "$PERIODIC_LAUNCH_AGENT" > /dev/null 2> /dev/null)

    AGENT_ACTIVE=$?

    if [ "$AGENT_ACTIVE" -eq "0" ]
    then

      launchctl unload "$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist"

      message "unloaded $PERIODIC_LAUNCH_AGENT"
    fi

    # Check for lock file

    if [ -e "$SUPPORT_FOLDER/var/$LOCK_FILE" ]
    then

      message "lock file found at $SUPPORT_FOLDER/var/$LOCK_FILE"

      PID=$(cat "$SUPPORT_FOLDER/var/$LOCK_FILE")

      message "a cloud backup is running with pid $PID... terminating"

      exit 0
    fi

    # Connect to data database

    db_connect

    if [ "$?" -ne 0 ]
    then

      message "failed to connect to database... terminating"

      exit 0
    fi

    message "connected to database"

    # Init manager

    manager_init

    message "manager initialized"

    # Write lock file

    echo $$ > "$SUPPORT_FOLDER/var/$LOCK_FILE"

    message "lock file written at $SUPPORT_FOLDER/var/$LOCK_FILE"

    # Set trim level

    TRIM_LEVEL="$2"

    # Loop over sources

    if [ $# -gt 0 ]
    then

      source "$SUPPORT_FOLDER"/etc/config.d/"$1"

      message "trimming $BACKUP_NAME to level $TRIM_LEVEL"

      trim

      if [ $? -ne 0 ]
      then

        message "trimming $BACKUP_NAME failed... terminating"

        exit 0
      fi

      message "completed trimming $BACKUP_NAME"
    else

      for CONFIG in "$SUPPORT_FOLDER"/etc/config.d/*
      do

        source "$CONFIG"

        message "trimming $BACKUP_NAME to level $TRIM_LEVEL"

        trim

        if [ $? -ne 0 ]
        then

          message "trimming $BACKUP_NAME failed... terminating"

          exit 0
        fi

        message "completed trimming $BACKUP_NAME"
      done
    fi

    # Save database

    /usr/local/bin/rclone copy "$SUPPORT_FOLDER/share/$DB_FILE" "$TARGET" $RCLONE_OPTS

    message "database saved"

    # Remove lock file

    rm "$SUPPORT_FOLDER/var/$LOCK_FILE"

    message "removed lock file at $SUPPORT_FOLDER/var/$LOCK_FILE"

    # Load launch agent

    if [ "$AGENT_ACTIVE" -eq "0" ]
    then

      launchctl load "$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist"

      message "loaded $PERIODIC_LAUNCH_AGENT"
    fi

    # Done

    ELAPSED=$(( $(date "+%s") - $TIMESTAMP ))

    DELTA=$( printf "%03d:%02d:%02d" $(( $ELAPSED / 3600 )) $(( ($ELAPSED % 3600) / 60 )) $(( $ELAPSED % 3600 % 60 )) )

    message "completed trimming cloud backup in $DELTA"
}

main "$@" 2>> "$HOME/Library/Logs/$LOG_FILE"