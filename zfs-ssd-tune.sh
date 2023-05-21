#!/usr/bin/env bash
# shellcheck disable=SC2034

# Simple CachyOS ZFS on SSD tuning script
# Made by Jiab77 - 2023
#
# Thanks to vnepogodin for the inspiration of the 'die' method :)
#
# TODO:
# - Detect SSDs
# - Detect installed kernel
#
# Commands:
# - Detect 'ashift' value
# zpool get -H ashift zpcachyos | awk '{ print $3 }'
#
# - Import with 'ashift' fix for SSD
# zpool import -Nl zpcachyos -o ashift=13
#
# - Import
# zpool import -Nl zpcachyos
#
# - Check
# zpool status -x
# zpool status -v zpcachyos
#
# - Export
# zpool export zpcachyos
#
# Version 0.0.1

# Options
set -o xtrace

# Config
DEBUG_MODE=false
DRY_RUN=false
FIX_ASHIFT=false
POOL_IMPORTED=false
POOL_MOUNTED=false
POOL_NAME="zpcachyos"
ASHIFT_VALUE_BACKUP="/root/.old_ashift_value"

# Overrides
[[ $# -eq 2 ]] && POOL_NAME="$2"

# Functions
function get_version() {
    grep -i 'version' "$0" | awk '{ print $3 }' | head -n1
}
function show_version() {
    echo -e "\nVersion: $(get_version)\n" ; exit
}
function show_usage() {
    echo -e "\nUsage: $(basename "$0") [options] [pool-name] -- Tune ZFS pool running on SSDs\n"
    echo -e "Options:\n"
    echo -e "-h|--help\tShow this message."
    echo -e "-v|--version\tShow script version."
    echo -e "-c|--check\tGet current state."
    echo -e "-p|--patch\tApply SSD patch."
    echo -e "-r|--restore\tRestore default state."
    echo -e "-d|--debug\tEnable debug mode."
    echo -e "-n|--dry-run\tSimulate changes, don't apply them."
    echo -e "\nDisclaimer:\n\n/!\ This script is still experimental so use it with caution. /!\ \n"
    exit
}
function die() {
    echo -e "\nError: $*\n"
    exit 255
}
function get_ashift_value() {
    local ASHIFT_VALUE

    echo -en "\nDetecting current 'ashift' value..."
    ASHIFT_VALUE=$(zpool get -H ashift "$POOL_NAME" | awk '{ print $3 }')
    echo -e " $ASHIFT_VALUE\n"

    if [[ -n $ASHIFT_VALUE && $ASHIFT_VALUE -eq 12 ]]; then
        read -rp "Fix 'ashift' value to 13 for SSDs? [y,N]: " CONFIRM_ASHIFT
        if [[ -n "$CONFIRM_ASHIFT" && "${CONFIRM_ASHIFT,,}" == "y" ]]; then
            echo -e "\nNoted. 'ashift' value will be changed during the import.\n"
            FIX_ASHIFT=true
        else
            echo -e "\nAll good, will not touch the 'ashift' value.\n"
            exit
        fi
    else
        die "This ZFS pool has been already tuned for SSDs."
    fi
}
function zpool_tune_import() {
    echo -e "\nChecking ZFS pool [$POOL_NAME] status...\n"
    [[ $(findmnt | grep -ci "$POOL_NAME") -ne 0 ]] && die "ZFS pool already mounted!"

    echo -e "\nSaving current 'ashift' value...\n"
    echo -n "$ASHIFT_VALUE" > "$ASHIFT_VALUE_BACKUP" || die "Could not backup current 'ashift' value"

    echo -e "\nImporting ZFS pool [$POOL_NAME] with fixed 'ashift' value for SSDs...\n"
    if [[ $DRY_RUN == true ]]; then
        echo -e "[DRY-RUN] Should run: zpool import -Nlf $POOL_NAME -o ashift=13\n"
    else
        if [[ $DEBUG_MODE == true ]]; then
            echo -e "[DEBUG] Running: zpool import -Nlf $POOL_NAME -o ashift=13\n"
        fi
        zpool import -Nlf "$POOL_NAME" -o ashift=13
        RET_CODE_IMPORT=$?

        if [[ $RET_CODE_IMPORT -eq 0 ]]; then
            POOL_IMPORTED=true
            echo -e "\nChecking imported ZFS pool status...\n"
            zpool status -x
            echo -e "\nGathering detailed ZFS pool status...\n"
            zpool status -v "$POOL_NAME"
        else
            die "Unable to import [$POOL_NAME] ZFS pool."
        fi
    fi
}
function zpool_tune_restore() {
    local OLD_ASHIFT_VALUE
    local ASHIFT_VALUE

    echo -e "\nChecking ZFS pool [$POOL_NAME] status...\n"
    [[ $(findmnt | grep -ci "$POOL_NAME") -ne 0 ]] && die "ZFS pool already mounted!"

    echo -en "\nDetecting current 'ashift' value..."
    ASHIFT_VALUE=$(zpool get -H ashift "$POOL_NAME" | awk '{ print $3 }')
    echo -e " $ASHIFT_VALUE\n"

    echo -e "\nChecking 'ashift' value backup file...\n"
    if [[ -f "$ASHIFT_VALUE_BACKUP" ]]; then
        OLD_ASHIFT_VALUE=$(cat "$ASHIFT_VALUE_BACKUP")

        echo -e "\nImporting ZFS pool [$POOL_NAME] with previous 'ashift' value...\n"
        if [[ -n "$OLD_ASHIFT_VALUE" ]]; then
            if [[ $DRY_RUN == true ]]; then
                echo -e "[DRY-RUN] Should run: zpool import -Nlf $POOL_NAME -o ashift=$OLD_ASHIFT_VALUE\n"
            else
                if [[ $DEBUG_MODE == true ]]; then
                    echo -e "[DEBUG] Running: zpool import -Nlf $POOL_NAME -o ashift=$OLD_ASHIFT_VALUE\n"
                fi
                zpool import -Nlf "$POOL_NAME" -o ashift="$OLD_ASHIFT_VALUE"
                RET_CODE_IMPORT=$?

                if [[ $RET_CODE_IMPORT -eq 0 ]]; then
                    POOL_IMPORTED=true
                    echo -e "\nChecking imported ZFS pool status...\n"
                    zpool status -x
                    echo -e "\nGathering detailed ZFS pool status...\n"
                    zpool status -v "$POOL_NAME"
                else
                    die "Unable to import [$POOL_NAME] ZFS pool."
                fi
            fi
        else
            die "Unable to get previous 'ashift' value."
        fi
    else
        die "Could not find 'ashift' backup file."
    fi
}
function zpool_export() {
    echo -e "\nExporting ZFS pool [$POOL_NAME]...\n"
    if [[ $DRY_RUN == true ]]; then
        echo -e "[DRY-RUN] Should run: zpool export $POOL_NAME\n"
    else
        [[ $POOL_IMPORTED == false ]] && die "The pool must be imported first prior being exported."
        [[ $POOL_MOUNTED == true ]] && echo -e "\nWarning: ZFS pool is still mounted. Will try to export anyway.\n"
        if [[ $DEBUG_MODE == true ]]; then
            echo -e "[DEBUG] Running: zpool export $POOL_NAME\n"
        fi
        zpool export "$POOL_NAME"
        RET_CODE_EXPORT=$?
        if [[ $RET_CODE_EXPORT -eq 0 ]]; then
            echo -e "\nDone.\n"
        else
            die "Unable to export [$POOL_NAME] ZFS pool."
        fi
    fi
}
function check_zfs_pool() {
    echo -e "\nChecking ZFS pool(s)...\n"
    zpool status -x "$POOL_NAME" || die "Could not find '$POOL_NAME' ZFS pool."
}

# Header
echo -e "\nSimple CachyOS ZFS on SSD tuning script"

# Checks
[[ $# -eq 0 ]] && show_usage

# Debug
if [[ $DEBUG_MODE == true ]]; then
    echo -e "\nArguments: $#\n"
fi

# Arguments
INDEX=0
for ARG in "$@"; do
    if [[ $DEBUG_MODE == true ]]; then
        echo "Arg $((INDEX++)): $ARG"
    fi

    case $ARG in
        "-h"|"--help") show_usage ;;
        "-v"|"--version") show_version ;;
        "-n"|"--dry-run") DRY_RUN=true ;;
        "-d"|"--debug") DEBUG_MODE=true ;;
        "-c"|"--check")
            get_ashift_value
            exit
        ;;
        "-p"|"--patch")
            get_ashift_value
            zpool_tune_import
            zpool_export
        ;;
        "-r"|"--restore")
            zpool_tune_restore
            zpool_export
        ;;
        *)
            die "Unsupported argument given: $ARG"
        ;;
    esac
done

# Main
check_zfs_pool
