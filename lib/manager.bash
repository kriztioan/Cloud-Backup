#!/bin/bash
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
