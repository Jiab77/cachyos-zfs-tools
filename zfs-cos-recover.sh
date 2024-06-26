#!/usr/bin/env bash
# shellcheck disable=SC2034

# Simple CachyOS ZFS boot recovery
# Made by Jiab77 - 2023
#
# Thanks to vnepogodin for the inspiration of the 'die' method :)
#
# TODO:
# - Detect SSDs
# - Detect installed kernel
#
# Sample recovery commands:
# - Detect 'ashift' value
# zpool get -H ashift zpcachyos | awk '{ print $3 }'
#
# - Import with 'ashift' fix for SSD
# zpool import -lf zpcachyos -o ashift=13
#
# - Import
# zpool import -lf zpcachyos
#
# - Check
# zpool status -x
# zpool status -v zpcachyos
#
# - List
# zfs list
# zfs list -t snapshot
#
# - Create mountpoints
# mkdir -pv /mnt/zfs/root/{home,var/cache,var/log}
#
# - Mount
# zfs set mountpoint=/mnt/zfs/root/home zpcachyos/ROOT/cos/home
# zfs set mountpoint=/mnt/zfs/root/ zpcachyos/ROOT/cos/root
# zfs set mountpoint=/mnt/zfs/root/var/cache zpcachyos/ROOT/cos/varcache
# zfs set mountpoint=/mnt/zfs/root/var/log zpcachyos/ROOT/cos/varlog
# zfs get mountpoint
# zfs mount zpcachyos/ROOT/cos/root
# zfs mount zpcachyos/ROOT/cos/home
# zfs mount zpcachyos/ROOT/cos/varcache
# zfs mount zpcachyos/ROOT/cos/varlog
# mount -v /dev/sda1 /mnt/zfs/root/boot
# mount -v /dev/nvme0n1p1 /mnt/zfs/root/boot
#
# - Chroot
# arch-chroot /mnt/zfs/root
#
# - Fix boot issue (from chroot)
# uname -a
# pacman -Sy linux-cachyos-headers,linux-cachyos-zfs
#
# - Leave chroot
# exit
#
# - Unmount pool
# zfs umount zpcachyos/ROOT/cos/home
# zfs umount zpcachyos/ROOT/cos/varcache
# zfs umount zpcachyos/ROOT/cos/varlog
# umount -v /mnt/zfs/root/boot
# zfs umount zpcachyos/ROOT/cos/root
# zpool export zpcachyos
#
# End of sample recovery commands
#
# Version 0.0.6

# Options
[[ -r $HOME/.debug ]] && set -o xtrace || set +o xtrace

# Config
DEBUG_MODE=false
DRY_RUN=false
FIX_ASHIFT=false
POOL_IMPORTED=false
POOL_MOUNTED=false
POOL_NAME="zpcachyos"
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
    echo -e "\nUsage: $(basename "$0") [options] -- Fix ZFS pool boot issues\n"
    echo -e "Options:\n"
    echo -e "-h|--help\tShow this message."
    echo -e "-v|--version\tShow script version."
    echo -e "-d|--debug\tEnable debug mode."
    echo -e "-n|--dry-run\tSimulate changes, don't apply them."
    echo -e "--name=<pool-name>\t\t\tSet pool name instead of default one."
    echo -e "\nDisclaimer:\n\n/!\ This script is still experimental so use it with caution. /!\ \n"
    exit
}
function die() {
    echo -e "\nError: $*\n" >&2
    exit 255
}
function get_ashift_value() {
    local ASHIFT_VALUE

    echo -en "\nDetecting 'ashift' value..."
    ASHIFT_VALUE=$(zpool get -H ashift "$POOL_NAME" | awk '{ print $3 }')
    echo -e " $ASHIFT_VALUE\n"

    if [[ $ASHIFT_VALUE -eq 12 ]]; then
        read -rp "Fix 'ashift' value to 13 for SSDs? [Y,N]: " CONFIRM_ASHIFT
        if [[ -n "$CONFIRM_ASHIFT" && "${CONFIRM_ASHIFT,,}" == "y" ]]; then
            echo -e "\nNoted. 'ashift' value will be changed during the import.\n"
            FIX_ASHIFT=true
        else
            echo -e "\nAll good, will not touch the 'ashift' value.\n"
        fi
    else
        echo -e "\nThis ZFS pool has been already tuned for SSDs.\n"
    fi
}
function zpool_import() {
    if [[ $FIX_ASHIFT == true ]]; then
        echo -e "\nImporting ZFS pool [$POOL_NAME] with fixed 'ashift' value for SSDs...\n"
        zpool import -lf "$POOL_NAME" -o ashift=13
        RET_CODE_IMPORT=$?
    else
        echo -e "\nImporting ZFS pool [$POOL_NAME]...\n"
        zpool import -lf "$POOL_NAME"
        RET_CODE_IMPORT=$?
    fi

    if [[ $RET_CODE_IMPORT -eq 0 ]]; then
        POOL_IMPORTED=true
        echo -e "\nChecking imported ZFS pool status...\n"
        zpool status -x "$POOL_NAME"
        echo -e "\nGathering detailed ZFS pool status...\n"
        zpool status -v "$POOL_NAME"
    else
        die "Unable to import [$POOL_NAME]."
    fi
}
function list_snapshots() {
    if [[ $POOL_IMPORTED == true ]]; then
        echo -e "\nGathering ZFS datasets...\n"
        zfs list
        echo -e "\nGathering ZFS snapshots...\n"
        zfs list -t snapshot
    fi
}
function create_mountpoints() {
    if [[ $POOL_IMPORTED == true ]]; then
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
        fi
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
function fix_boot() {
    if [[ $POOL_MOUNTED == true ]]; then
        echo -e "Fixing ZFS bootloader...\n"
        if [[ $DRY_RUN == true ]]; then
            echo -e "[DRY-RUN] Should run: arch-chroot $MOUNTPOINT pacman -Sy linux-cachyos-headers,linux-cachyos-zfs\n"
        else
            arch-chroot "$MOUNTPOINT" pacman -Sy linux-cachyos-headers,linux-cachyos-zfs
            RET_CODE_FIX=$?
            if [[ $RET_CODE_FIX -eq 0 ]]; then
                echo -e "\nDone.\n"
            else
                die "Unable to fix ZFS bootloader."
            fi
        fi
    else
        die "Can't chroot in unmounted ZFS pool."
    fi
}
function load_chroot() {
    if [[ $POOL_MOUNTED == true ]]; then
        echo -e "Loading chroot...\n"
        if [[ $DRY_RUN == true ]]; then
            echo -e "[DRY-RUN] Should run: arch-chroot $MOUNTPOINT\n"
        else
            arch-chroot "$MOUNTPOINT"
            RET_CODE_FIX=$?
            if [[ $RET_CODE_FIX -eq 0 ]]; then
                echo -e "\nDone.\n"
            else
                die "Unable to load chroot."
            fi
        fi
    else
        die "Can't chroot in unmounted ZFS pool."
    fi
}
function zfs_export() {
    if [[ $POOL_MOUNTED == false ]]; then
        echo -e "\nExporting ZFS pool [$POOL_NAME]...\n"
        zpool export "$POOL_NAME"
        RET_CODE_EXPORT=$?
    else
        echo -e "\nWarning: ZFS pool is not unmounted. Will try to export anyway.\n"
        zpool export "$POOL_NAME"
        RET_CODE_EXPORT=$?
    fi
    if [[ $RET_CODE_EXPORT -eq 0 ]]; then
        echo -e "\nDone.\n"
    else
        die "Unable to export [$POOL_NAME] ZFS pool."
    fi
}
function check_zfs_pool() {
    echo -e "\nChecking ZFS pool(s)...\n"
    zpool status -x 2>/dev/null || die "Could not find any ZFS pool."
}
function init_recovery() {
    # Ask before init recovery
    echo ; read -rp "This script will initialize CachyOS ZFS pool recovery process, continue? [Y,N]: " CONFIRM_RECOVERY
    if [[ -n $CONFIRM_RECOVERY && "${CONFIRM_RECOVERY,,}" == "y" ]]; then
        echo -e "\nAll good, let's do it then!.\n"
    else
        echo -e "\nNo problem, see you next time ;).\n"
        exit
    fi

    # Init recovery
    echo -e "\nInitializing CachyOS ZFS pool recovery...\n"
    check_zfs_pool
    get_ashift_value
    echo ; read -rp "Importing ZFS pool, continue? [Y,N]: " CONFIRM_IMPORT
    [[ -n $CONFIRM_IMPORT && "${CONFIRM_IMPORT,,}" == "y" ]] && zpool_import
    echo ; read -rp "Displaying existing snapshots, continue? [Y,N]: " CONFIRM_SHOW_SNAP
    [[ -n $CONFIRM_SHOW_SNAP && "${CONFIRM_SHOW_SNAP,,}" == "y" ]] && list_snapshots
    echo ; read -rp "Creating mountpoints, continue? [Y,N]: " CONFIRM_MOUNTPOINTS
    [[ -n $CONFIRM_MOUNTPOINTS && "${CONFIRM_MOUNTPOINTS,,}" == "y" ]] && create_mountpoints
    echo ; read -rp "Mounting ZFS pool, continue? [Y,N]: " CONFIRM_MOUNT
    [[ -n $CONFIRM_MOUNT && "${CONFIRM_MOUNT,,}" == "y" ]] && zfs_mount
    echo ; read -rp "Loading 'chroot' and fix boot, continue? [Y,N]: " CONFIRM_FIX
    [[ -n $CONFIRM_FIX && "${CONFIRM_FIX,,}" == "y" ]] && fix_boot
    echo ; read -rp "Unmounting ZFS pool, continue? [Y,N]: " CONFIRM_UMOUNT
    [[ -n $CONFIRM_UMOUNT && "${CONFIRM_UMOUNT,,}" == "y" ]] && zfs_unmount
    echo ; read -rp "Exporting ZFS pool, continue? [Y,N]: " CONFIRM_EXPORT
    [[ -n $CONFIRM_EXPORT && "${CONFIRM_EXPORT,,}" == "y" ]] && zfs_export
}

# Header
echo -e "\nSimple ZFS boot recovery script for CachyOS - v$(get_version)"

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
        "--name="*)
            [[ -z "${ARG/--name=/}" ]] && die "Missing pool name."
            POOL_NAME="${ARG/--name=/}"
        ;;
        *)
            die "Unsupported argument given: $ARG"
        ;;
    esac
done

# Checks
[[ $(id -u) -ne 0 ]] && die "This script must be run as root or with 'sudo'."
[[ $(findmnt | grep -ci "$POOL_NAME") -ne 0 ]] && die "ZFS pool already mounted!"

# Main
init_recovery
