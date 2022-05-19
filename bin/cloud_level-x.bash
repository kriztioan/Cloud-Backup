#!/bin/bash
###
#  @file   cloud_level-x.bash
#  @brief  Perform Incremental Backup
#  @author KrizTioaN (christiaanboersma@hotmail.com)
#  @date   2021-07-24
#  @note   BSD-3 licensed
#
###############################################

# ignore SIGTERM

trap -- '' SIGTERM

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

function backup {

    # Check for target

    message "checking target"

    /usr/local/bin/rclone ls "$TARGET" $RCLONE_OPTS >/dev/null 2>&1

    if [ ! $? -eq 0 ]; then

        message "target ($TARGET) not available... terminating"

        if [ -e /usr/local/bin/growlnotify ]; then

            /usr/local/bin/growlnotify --sticky --name "Cloud Backup" --image "$ICON" --title "Cloud Backup" --message "$BACKUP_NAME: Target not available, please configure $TARGET and/or check your internet connection" &>/dev/null
        fi

        return 1
    fi

    # Check for source

    message "checking source"

    if [ ! -d "$SOURCE" ]; then

        message "source ($SOURCE) not available... terminating"

        if [ -e /usr/local/bin/growlnotify ]; then

            /usr/local/bin/growlnotify --sticky --name "Cloud Backup" --image "$ICON" --title "Cloud Backup" --message "$BACKUP_NAME: Source not available, please attach the network/USB-drive containing $SOURCE" &>/dev/null
        fi

        return 2
    fi

    # Getting last update

    db_last "$BACKUP_NAME"

    if [ $? -ne 0 ]; then

        message "no backups found... terminating"

        message "all periodic level-x backups have been canceled"

        if [ -e /usr/local/bin/growlnotify ]; then

            /usr/local/bin/growlnotify --sticky --name "Cloud Backup" --image "$ICON" --title "Cloud Backup" --message "$BACKUP_NAME: No backups found, please perform one manually first; all periodic level-x backups have been canceled" &>/dev/null
        fi

        return 3
    fi

    message "last update (level-$LEVEL) dated $(date -r $DATE)"

    /usr/local/bin/rclone copy "$TARGET$BACKUP_NAME"."$LEVEL".catalogue.1.dar . $RCLONE_OPTS 2>/dev/null

    if [ ! $? -eq 0 ]; then

        message "no level-$LEVEL catalogue found... terminating"

        message "all periodic level-x backups have been canceled"

        if [ -e /usr/local/bin/growlnotify ]; then

            /usr/local/bin/growlnotify --sticky --name "Cloud Backup" --image "$ICON" --title "Cloud Backup" --message "$BACKUP_NAME: No level-$LEVEL backup found, please perform one manually first; all periodic level-x backups have been canceled" &>/dev/null
        fi

        return 4
    fi

    message "retrieved level-$LEVEL catalogue"

    LEVEL=$(($LEVEL + 1))

    # Do dar

    echo -n 0 >wait_pid

    message "dar started"

    message "doing a level-$LEVEL backup"

    caffeinate /usr/local/bin/dar -q -Q -asecu \
        -c "$BACKUP_NAME"."$LEVEL" \
        -s "$DAR_BYTES" \
        -R "$SOURCE" \
        -E "'$DAR_SCRIPT' create %b.%N.dar $TARGET %n $BACKUP_NAME.$LEVEL" \
        -A "$BACKUP_NAME".$(($LEVEL - 1))".catalogue" \
        --min-digits 6 \
        --on-fly-isolate "$BACKUP_NAME.$LEVEL.catalogue" \
        --exclude ".DS_Store" \
        --prune ".DocumentRevisions-V100" \
        --prune ".TemporaryItems" \
        --prune ".Trashes"

    DAR_CODE=$?

    rm -f "$BACKUP_NAME".$(($LEVEL - 1))".catalogue"

    message "dar finished with code $DAR_CODE"

    if [ $DAR_CODE -ne 0 ]; then

        message "please check the log file for any errors/warnings"

        if [ -e /usr/local/bin/growlnotify ]; then

            /usr/local/bin/growlnotify --sticky --name "Cloud Backup" --image "$ICON" --title "Cloud Backup" --message "$BACKUP_NAME: WARNING/ERRORS encountered; please check the log file" &>/dev/null
        fi
    fi

    WAIT_PID=$(cat wait_pid)

    if [ $WAIT_PID -ne 0 ]; then

        message "- wait on $(printf "$BACKUP_NAME.$LEVEL.%06d.dar" $(cat "$BACKUP_NAME".$LEVEL.slices))"

        while kill -0 "$WAIT_PID" 2>/dev/null; do

            sleep 0.5
        done
    fi

    rm -f wait_pid

    BYTES=$(cat ./"$BACKUP_NAME"."$LEVEL".bytes)

    rm -f ./"$BACKUP_NAME"."$LEVEL".bytes

    message "$BACKUP_NAME: archived $(human $BYTES)"

    TOTAL_BYTES=$(($TOTAL_BYTES + $BYTES))

    # Archiving level-x catalogue

    message "archiving level-$LEVEL catalogue"

    /usr/local/bin/rclone copy "$BACKUP_NAME"."$LEVEL".catalogue.1.dar "$TARGET" $RCLONE_OPTS

    # Commit to database

    message "committing to database"

    db_insert "$BACKUP_NAME" $LEVEL $BYTES $(cat "$BACKUP_NAME".$LEVEL.slices)

    rm -f "$BACKUP_NAME".$LEVEL.slices

    # Add catalogue to manager

    message "adding catalogue to manager"

    manager_add "$BACKUP_NAME"."$LEVEL".catalogue "$BACKUP_NAME"."$LEVEL "

    rm -f "$BACKUP_NAME"."$LEVEL".catalogue.1.dar

    return 0
}

function main {

    # Starting

    TIMESTAMP=$(date +"%s")

    message "starting incremental backup to the Cloud (PID $$)"

    # Unload the launch agent

    ACTIVE=$(launchctl list "$PERIODIC_LAUNCH_AGENT" >/dev/null 2>&1)

    if [ $? -eq "0" ]; then

        launchctl unload "$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist"

        message "unloaded $PERIODIC_LAUNCH_AGENT"
    fi

    # Check for Growl and when available notify

    if [ -e /usr/local/bin/growlnotify ]; then

        /usr/local/bin/growlnotify --sticky --name "Cloud Backup" --image "$ICON" --title "Cloud Backup" --message "$(date +"Incremental backup to the Cloud started at %A %d %b %Y, %H:%M:%S")" &>/dev/null
    fi

    # Check for lock file

    if [ -e "$SUPPORT_FOLDER/var/$LOCK_FILE" ]; then

        message "lock file found at $SUPPORT_FOLDER/var/$LOCK_FILE"

        PID=$(cat "$SUPPORT_FOLDER/var/$LOCK_FILE")

        message "cloud backup already running with pid $PID... terminating"

        exit 0
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

    # Stop mediaanalysisd

    launchctl disable gui/$UID/com.apple.mediaanalysisd

    launchctl kill -TERM gui/$UID/com.apple.mediaanalysisd

    # Stop photoanalysisd

    launchctl disable gui/$UID/com.apple.photoanalysisd

    launchctl kill -TERM gui/$UID/com.apple.photoanalysisd

    # Loop over sources

    TOTAL_BYTES=0

    if [ $# -gt 0 ]; then

        source "$SUPPORT_FOLDER"/etc/config.d/"$1"

        message "Doing $BACKUP_NAME"

        backup

        if [ $? -ne 0 ]; then

            message "$BACKUP_NAME failed... terminating"

            abort 0
        fi

        message "Completed $BACKUP_NAME"
    else

        for CONFIG in "$SUPPORT_FOLDER"/etc/config.d/*; do

            source "$CONFIG"

            message "Doing $BACKUP_NAME"

            backup

            if [ $? -ne 0 ]; then

                message "$BACKUP_NAME failed... terminating"

                abort 0
            fi

            message "Completed $BACKUP_NAME"
        done
    fi

    # Re-start mediaanalysisd

    launchctl disable gui/$UID/com.apple.mediaanalysisd

    # Re-start photoanalysisd

    launchctl enable gui/$UID/com.apple.photoanalysisd

    # Save database

    /usr/local/bin/rclone delete "$TARGET$DB_FILE" $RCLONE_OPTS

    /usr/local/bin/rclone copy "$SUPPORT_FOLDER/share/$DB_FILE" "$TARGET" $RCLONE_OPTS

    message "database saved"

    # Save timestamp

    date +"%s" >"$SUPPORT_FOLDER/var/$TIMESTAMP_FILE"

    /usr/local/bin/rclone delete "$TARGET$TIMESTAMP_FILE" -q

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
	<string>net.ddns.christiaanboersma.cloud_backup.periodic</string>
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

    message "next incremental backup scheduled to run at 10:00 AM on $(date -v +${DAY_INTERVAL}d +"%A, %B %e %Y")"

    # Load launch agent

    launchctl load "$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist"

    message "loaded $PERIODIC_LAUNCH_AGENT"

    # Done

    ELAPSED=$(($(date "+%s") - $TIMESTAMP))

    DELTA=$(printf "%03d:%02d:%02d" $(($ELAPSED / 3600)) $((($ELAPSED % 3600) / 60)) $(($ELAPSED % 3600 % 60)))

    message "completed incremental backup to the Cloud in $DELTA"

    # Check for Growl and when available notify

    if [ -e /usr/local/bin/growlnotify ]; then

        /usr/local/bin/growlnotify --sticky --name "Cloud Backup" --image "$ICON" --title "Cloud Backup" --message "$(date +"Completed incremental backup to the Cloud at %A %d %b %Y, %H:%M:%S; archived $(human $TOTAL_BYTES) in $DELTA ")" &>/dev/null
    fi
}

main "$@" >>"$HOME/Library/Logs/$LOG_FILE" 2>&1
