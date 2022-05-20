#!/bin/bash
###
#  @file   db.bash
#  @brief  Database Bash Functions
#  @author KrizTioaN (christiaanboersma@hotmail.com)
#  @date   2021-07-24
#  @note   BSD-3 licensed
#
###############################################

function db_connect {

  if [ ! -e "$SUPPORT_FOLDER/share/$DB_FILE" ]; then

    db_create

    return
  fi

  return 0
}

function db_create {

  sqlite3 "$SUPPORT_FOLDER/share/$DB_FILE" "CREATE TABLE backups (name TEXT, level INTEGER, date DATE, size INTEGER, slices INTEGER, PRIMARY KEY (name, level));"
}

function db_insert {

  sqlite3 "$SUPPORT_FOLDER/share/$DB_FILE" "INSERT INTO backups (name, level, size, slices, date) VALUES ('$1', $2, $3, $4, datetime('now'));"
}

function db_select {

  DB_RESULT=$(sqlite3 "$SUPPORT_FOLDER/share/$DB_FILE" "SELECT name, level, strftime('%s', date), size, slices FROM backups WHERE name='$1' AND level=$2 LIMIT 1;")

  if [ -z "$DB_RESULT" ]; then

    return 1
  fi

  IFS='|' read NAME LEVEL DATE SIZE SLICES <<<"$DB_RESULT"

  unset DB_RESULT
}

function db_delete {

  sqlite3 "$SUPPORT_FOLDER/share/$DB_FILE" "DELETE FROM backups WHERE name='$1' AND level=$2;"
}

function db_last {

  DB_RESULT=$(sqlite3 "$SUPPORT_FOLDER/share/$DB_FILE" "SELECT name, level, strftime('%s', date), size, slices FROM backups WHERE name='$1' AND level=(SELECT MAX(level) FROM backups WHERE name='$1') LIMIT 1;")

  if [ -z "$DB_RESULT" ]; then

    return 1
  fi

  IFS='|' read NAME LEVEL DATE SIZE SLICES <<<"$DB_RESULT"

  unset DB_RESULT
}

function db_trim {

  sqlite3 "$SUPPORT_FOLDER/share/$DB_FILE" "DELETE FROM backups WHERE name='$1' AND level>$2;"
}
