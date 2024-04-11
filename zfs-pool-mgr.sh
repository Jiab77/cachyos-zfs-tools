#!/usr/bin/env bash
# shellcheck disable=SC2034

# Simple CachyOS ZFS pool manager
# Made by Jiab77 - 2023
#
# Thanks to vnepogodin for the inspiration of the 'die' method :)
#
# TODO:
# - Detect SSDs
# - Detect installed kernel
#
# Version 0.0.0

# Options
[[ -r $HOME/.debug ]] && set -o xtrace || set +o xtrace

# Colors
NC="\033[0m"
NL="\n"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
RED="\033[1;31m"
WHITE="\033[1;37m"
PURPLE="\033[1;35m"

# Config
DEBUG_MODE=false
DRY_RUN=false
HOST_NAME=$(hostname -s)
POOL_NAME=$(zpool list -H | awk '{ print $1 }')
MOUNTPOINT="/mnt/zfs/root"
MOUNTPOINT_CREATED=false

# Functions
function get_version() {
    grep -i 'version' "$0" | awk '{ print $3 }' | head -n1
}
function show_version() {
    echo -e "\nVersion: $(get_version)\n" ; exit
}
function show_usage() {
    echo -e "\nUsage: $(basename "$0") <ACTION> [OPTIONS] -- Manage ZFS snapshots\n"
    echo -e "Action:\n"
    echo -e "detect\t\t\t\t\tSearch for existing pool."
    echo -e "status\t\t\t\t\tShow pool status."
    echo -e "history\t\t\t\t\tShow all changes done on the pool."
    echo -e "\nOptions:\n"
    echo -e "-h|--help\t\t\t\tShow this message."
    echo -e "-v|--version\t\t\t\tShow script version."
    echo -e "-d|--debug\t\t\t\tEnable debug mode."
    echo -e "-n|--dry-run\t\t\t\tSimulate requested actions, don't execute them."
    echo -e "--name=<pool-name>\t\t\tSet pool name instead of default one."
    echo -e "${NL}${WHITE}Disclaimer:${NL}${NL} ${RED}/${YELLOW}!${RED}\ ${YELLOW}This script is still experimental so use it with caution. ${RED}/${YELLOW}!${RED}\ ${NC}${NL}"
    exit
}
function die() {
    echo -e "\nError: $*\n" >&2
    exit 255
}
function zppol_detect() {
    echo -e "\nSearching for existing ZFS pool(s)...\n"
    if [[ $DRY_RUN == true ]]; then
        echo -e "[DRY-RUN] Should run: zpool status -x\n"
    else
        if [[ $DEBUG_MODE == true ]]; then
            echo -e "[DEBUG] Running: zpool status -x\n"
        fi
        zpool status -x
        echo -e "\nDone.\n"
    fi
}
function zppol_status() {
    echo -e "\nShowing ZFS pool status...\n"
    if [[ $DRY_RUN == true ]]; then
        echo -e "[DRY-RUN] Should run: zpool status -v $POOL_NAME\n"
    else
        if [[ $DEBUG_MODE == true ]]; then
            echo -e "[DEBUG] Running: zpool status -v $POOL_NAME\n"
        fi
        zpool status -v "$POOL_NAME"
        echo -e "\nDone.\n"
    fi
}
function zpool_history() {
    [[ $(id -u) -ne 0 ]] && die "You must run this action as root or with 'sudo'."

    echo -e "\nGathering ZFS pool history...\n"
    if [[ $DRY_RUN == true ]]; then
        echo -e "[DRY-RUN] Should run: zpool history\n"
    else
        if [[ $DEBUG_MODE == true ]]; then
            echo -e "[DEBUG] Running: zpool history\n"
        fi
        zpool history
        echo -e "\nDone.\n"
    fi
}
function create_mountpoints() {
    if [[ ! -d "$MOUNTPOINT" ]]; then
        echo -en "\nCreating mountpoint [$MOUNTPOINT]..."
        mkdir -p "$MOUNTPOINT"/{home,var/cache,var/log}
        RET_CODE_CREATE=$?
        if [[ $RET_CODE_CREATE -eq 0 ]]; then
            MOUNTPOINT_CREATED=true
            echo -e " done.\n"
        else
            die "Unable to create mountpoint."
        fi
    else
        MOUNTPOINT_CREATED=true
    fi
}
function zfs_mount() {
    if [[ $MOUNTPOINT_CREATED == true ]]; then
        echo -e "\nMounting ZFS pool to $MOUNTPOINT...\n"
        zfs set mountpoint="$MOUNTPOINT"/home "$POOL_NAME"/ROOT/cos/home
        zfs set mountpoint="$MOUNTPOINT" "$POOL_NAME"/ROOT/cos/root
        zfs set mountpoint="$MOUNTPOINT"/var/cache "$POOL_NAME"/ROOT/cos/varcache
        zfs set mountpoint="$MOUNTPOINT"/var/log "$POOL_NAME"/ROOT/cos/varlog
        zfs get mountpoint
        zfs mount "$POOL_NAME"/ROOT/cos/root
        zfs mount "$POOL_NAME"/ROOT/cos/home
        zfs mount "$POOL_NAME"/ROOT/cos/varcache
        zfs mount "$POOL_NAME"/ROOT/cos/varlog
        mount -v /dev/sda1 "$MOUNTPOINT"/boot
        if [[ $(findmnt | grep -ci "$POOL_NAME") -ne 0 ]]; then
            POOL_MOUNTED=true
            echo -e "\nDone.\n"
        else
            die "Unable to mount ZFS pool."
        fi
    fi
}
function zfs_unmount() {
    if [[ $MOUNTPOINT_CREATED == true ]]; then
        echo -e "\nUnmounting ZFS pool from $MOUNTPOINT...\n"
        zfs umount "$POOL_NAME"/ROOT/cos/home
        zfs umount "$POOL_NAME"/ROOT/cos/varcache
        zfs umount "$POOL_NAME"/ROOT/cos/varlog
        umount -v "$MOUNTPOINT"/boot
        zfs umount "$POOL_NAME"/ROOT/cos/root
        zfs set mountpoint=/home "$POOL_NAME"/ROOT/cos/home
        zfs set mountpoint=/ "$POOL_NAME"/ROOT/cos/root
        zfs set mountpoint=/var/cache "$POOL_NAME"/ROOT/cos/varcache
        zfs set mountpoint=/var/log "$POOL_NAME"/ROOT/cos/varlog
        zfs get mountpoint
        if [[ $(findmnt | grep -ci "$POOL_NAME") -eq 0 ]]; then
            POOL_MOUNTED=false
            echo -e "\nDone.\n"
        else
            die "Unable to unmount ZFS pool."
        fi
    fi
}
function init_pool_mgr() {
    case $ZFS_ACTION in
        "detect") zpool_detect ;;
        "status") zpool_status ;;
        "history") zpool_history ;;
    esac
}

# Header
echo -e "\nSimple ZFS pool manager for CachyOS - v$(get_version)\n"

# Checks
[[ $# -eq 0 ]] && show_usage

# Arguments
INDEX=0
for ARG in "$@"; do
    if [[ $DEBUG_MODE == true ]]; then
        echo "Arg $((INDEX++)): $ARG"
    fi

    case $ARG in
        "detect"|"status"|"history") ZFS_ACTION="$ARG" ;;
        "-h"|"--help") show_usage ;;
        "-v"|"--version") show_version ;;
        "-n"|"--dry-run") DRY_RUN=true ;;
        "-d"|"--debug") DEBUG_MODE=true ;;
        "--mountpoint="*)
            [[ -z "${ARG/--mountpoint=/}" ]] && die "Missing mountpoint."
            MOUNTPOINT="${ARG/--mountpoint=/}"
        ;;
        "--name="*)
            [[ -z "${ARG/--name=/}" ]] && die "Missing pool name."
            POOL_NAME="${ARG/--name=/}"
        ;;
        *)
            die "Unsupported argument given: $ARG"
        ;;
    esac
done

# Main
init_pool_mgr
