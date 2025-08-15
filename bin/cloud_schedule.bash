#!/bin/bash
###
#  @file   cloud_schedule.bash
#  @brief  Schedule Cloud Backups
#  @author KrizTioaN (christiaanboersma@hotmail.com)
#  @date   2021-07-24
#  @note   BSD-3 licensed
#
###############################################

# Support folder location

SUPPORT_FOLDER="$HOME/Library/Application Support/Cloud Backup"

# Source variables

source "$SUPPORT_FOLDER/etc/config"

# Functions

function message {
  /usr/local/bin/unbuffer echo "$(date "+%m-%d-%Y %H:%M:%S: $1")"
}

function report {

  DAYS="$1"

  if [ $DAYS -gt $DAY_INTERVAL ]; then

    if [ $((($DAYS - $DAY_INTERVAL) % $DAYS_REPORT)) -eq 0 ]; then

      REPORT=0

      if [ -e "$SUPPORT_FOLDER"/var/report ]; then

        REPORT=$(cat "$SUPPORT_FOLDER"/var/report)
      fi

      if [ $REPORT -ne $DAYS ]; then

        message "backups are $DAYS days old... consider doing a level-x backup"

        if [ -e /usr/local/bin/growlnotify ]; then

          /usr/local/bin/growlnotify --sticky --name "Cloud Backup" --image "$ICON" --title "Cloud Backup" --message "Cloud backups are $DAYS days old; consider doing a level-x backup" &>/dev/null
        fi

        echo -n $DAYS >"$SUPPORT_FOLDER"/var/report
      fi
    fi
  fi
}

function main {

  # Starting

  message "cloud backup scheduling"

  # Unload the launch agent

  ACTIVE=$(launchctl list "$PERIODIC_LAUNCH_AGENT" >/dev/null 2>/dev/null)

  if [ $? -eq "0" ]; then

    launchctl unload "$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist"

    message "unloaded $PERIODIC_LAUNCH_AGENT"
  fi

  # Getting timestamp

  message "checking timestamp"

  if [ -e "$SUPPORT_FOLDER/var/$TIMESTAMP_FILE" ]; then

    TIMESTAMP=$(cat "$SUPPORT_FOLDER/var/$TIMESTAMP_FILE")

    message "last backup is dated $(date -r $TIMESTAMP)"

    # Shift timestamp to beginning of day

    TIMESTAMP=$(date -j -f "%a %b %d %T %Z %Y" "$(date -r $TIMESTAMP "+%a %b %d 00:00:00 %Z %Y")" "+%s")
  else

    message "no backups found... no level-x backups scheduled"

    #report -1

    exit 0
  fi

  # Calculate elapsed time from near midnight today

  MIDNIGHT=$(date -j -f "%a %b %d %T %Z %Y" "$(date "+%a %b %d 23:59:59 %Z %Y")" "+%s")

  ELAPSED=$(($MIDNIGHT - $TIMESTAMP + 1))

  DAYS=$(($ELAPSED / 86400))

  # Check for lock file

  if [ -e "$SUPPORT_FOLDER/var/$LOCK_FILE" ]; then

    message "lock file found at $SUPPORT_FOLDER/var/$LOCK_FILE"

    PID=$(cat "$SUPPORT_FOLDER/var/$LOCK_FILE")

    message "backup running with pid $PID... no level-x backups scheduled"

    exit 0
  fi

  # Check for SSID

  message "checking network"

  SSID=$(system_profiler SPAirPortDataType | awk '/Current Network Information:/ {getline;$1=$1;printf "%s", substr($1, 1, length($1)-1); exit}')

  if [ -z "$SSID" ]; then

    message "no network connection... no level-x backups scheduled"

    report $DAYS

    exit 0
  fi

  if [ "$SSID" != "$NETWORK" ]; then

    message "not on network '$NETWORK' on '$SSID' instead... no level-x backups scheduled"

    report $DAYS

    exit 0
  fi

  # Check sources availability

  message "checking sources"

  for CONFIG in "$SUPPORT_FOLDER"/etc/config.d/*; do

    source "$CONFIG"

    if [ ! -d "$SOURCE" ]; then

      message "not all sources are available... no level-x backups scheduled"

      report $DAYS

      exit 0
    fi
  done

  # Establish next backup

  if [ $DAYS -gt $DAY_INTERVAL ]; then

    read -r -d '' INTERVAL <<EOF

    <key>StartInterval</key>
       <integer>300</integer>
EOF

    message "backup is $DAYS days old... level-x backup scheduled to start in 5 minutes"
  else

    DELTA_DAYS=$(($DAY_INTERVAL - $DAYS + 1))

    read -r -d '' INTERVAL <<EOF

  <key>StartCalendarInterval</key>
  <dict>
    <key>Minute</key>
       <integer>0</integer>
    <key>Hour</key>
    <integer>10</integer>
    <key>Day</key>
    <integer>$(date -v +${DELTA_DAYS}d +"%d")</integer>
    <key>Month</key>
    <integer>$(date -v +${DELTA_DAYS}d +"%m")</integer>
        </dict>
EOF

    message "backup is $DAYS days old... level-x backups scheduled to run at 10:00 AM on $(date -v +${DELTA_DAYS}d +"%A, %B %e %Y")"
  fi

  echo 0 >"$SUPPORT_FOLDER"/var/report

  cat >"$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist" <<EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
$INTERVAL
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
    <string>$HOME/Library/Application\ Support/Cloud\ Backup/bin/cloud_level-x.bash; disown</string>
  </array>
</dict>
</plist>
EOL

  message "written $PERIODIC_LAUNCH_AGENT"

  # Load launch agent

  launchctl load "$SUPPORT_FOLDER/share/$PERIODIC_LAUNCH_AGENT.plist"

  message "loaded $PERIODIC_LAUNCH_AGENT"

  # Done

  message "cloud backup scheduling finished"
}

main >>"$HOME/Library/Logs/$LOG_FILE" 2>&1
