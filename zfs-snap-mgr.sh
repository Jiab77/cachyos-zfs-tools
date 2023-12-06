#!/usr/bin/env bash
# shellcheck disable=SC2034

# Simple CachyOS ZFS snapshot manager
# Made by Jiab77 - 2023
#
# Thanks to vnepogodin for the inspiration of the 'die' method :)
#
# TODO:
# - Implement rollback feature
# - Implement compressed stream file output
# - Implement SSH connection
#
# Version 0.0.9

# Options
set +o xtrace

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
NO_HEADER=false
RECURSIVE_MODE=false
INCREMENTAL_MODE=false
NO_PREFIX=false
USE_GIVEN_NAME=false
USE_COMPRESSION=false
COMPRESS_WITH_GZIP=false
COMPRESS_WITH_XZ=false
SAVE_ALL=false

# Internals
HOST_NAME=$(hostname -s)
POOL_NAME=$(zpool list -H | awk '{ print $1 }')
FIRST_SNAP=$(zfs list -t snapshot -H | head -n1 | awk '{ print $1 }')
PREV_SNAP=$(zfs list -t snapshot -H | grep -v "/" | tail -n2 | head -n1 | awk '{ print $1 }')
LAST_SNAP=$(zfs list -t snapshot -H | grep -v "/" | tail -n1 | awk '{ print $1 }')
SNAP_COUNT=$(zfs list -t snapshot -H | grep -cv "/")
SNAP_MOUNT=$(grep "$(id -un 1000)" /etc/passwd | head -n1 | sed -e 's/:/ /g' | awk '{ print $6 }')
SNAP_BASE="Data/Snapshots"
SNAP_FOLDER="$SNAP_MOUNT/$SNAP_BASE/$HOST_NAME"
SNAP_PREFIX="initial"
SNAP_DATE=$(date "+%Y%m%d%H%M%S")
SNAP_NAME="${SNAP_PREFIX}-${SNAP_DATE}"

# Functions
function get_version() {
    grep -i 'version' "$0" | awk '{ print $3 }' | head -n1
}
function print_header() {
    if [[ $NO_HEADER == false ]]; then
        echo -e "\nSimple ZFS snapshot manager for CachyOS - v$(get_version)"
    fi
}
function show_version() {
    echo -e "\nVersion: $(get_version)\n" ; exit
}
function show_usage() {
    print_header
    echo -e "\nUsage: $(basename "$0") <ACTION> [OPTIONS] -- Manage ZFS snapshots\n"
    echo -e "Action:\n"
    echo -e "help\t\t\t\t\tShow this message and exit."
    echo -e "list\t\t\t\t\tList existing snapshots."
    echo -e "create\t\t\t\t\tCreate new snapshot."
    echo -e "send\t\t\t\t\tSend snapshot to remote file. (Inside a remotely mapped folder only)"
    echo -e "delete\t\t\t\t\tDelete given snapshot."
    echo -e "dump\t\t\t\t\tDump snapshot file content."
    echo -e "diff\t\t\t\t\tShow differences between last snapshot and now."
    echo -e "history\t\t\t\t\tShow all changes done on the pool."
    echo -e "\nOptions:\n"
    echo -e "-h|--help\t\t\t\tShow this message and exit."
    echo -e "-v|--version\t\t\t\tShow script version and exit."
    echo -e "-d|--debug\t\t\t\tEnable debug mode."
    echo -e "-n|--dry-run\t\t\t\tSimulate requested actions, don't execute them."
    echo -e "-r|--recursive\t\t\t\tRun <ACTION> recursively."
    echo -e "-i|--incremental\t\t\tMake incremental snapshot files."
    echo -e "--all\t\t\t\t\tCombine all snapshots in a single file."
    echo -e "--no-header\t\t\t\tAvoid printing script header."
    echo -e "--no-prefix\t\t\t\tUse date only as snapshot name."
    echo -e "--mountpoint=<remote-mapped-folder>\tSet locally mapped remote snapshot folder."
    echo -e "--name=<snapshot-name>\t\t\tSet snapshot name instead of default one. [Use '--no-prefix' to avoid adding the current date to the name]"
    echo -e "--compress=<gzip,xz>\t\t\tCompress snapshot file in given format. [NOT IMPLEMENTED YET]"
    echo -e "${NL}${WHITE}Disclaimer:${NL}${NL} ${RED}/${YELLOW}!${RED}\ ${YELLOW}This script is still experimental so use it with caution. ${RED}/${YELLOW}!${RED}\ ${NC}${NL}"
    exit
}
function die() {
    echo -e "${NL}${RED}Error: $*${NC}${NL}" >&2
    exit 255
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
function zfs_list() {
    echo -e "\nListing ZFS snapshots...\n"
    if [[ $DRY_RUN == true ]]; then
        echo -e "[DRY-RUN] Should run: zfs list -t snapshot\n"
    else
        if [[ $DEBUG_MODE == true ]]; then
            echo -e "[DEBUG] Running: zfs list -t snapshot\n"
        fi
        zfs list -t snapshot
    fi
}
function zfs_create() {
    [[ $(id -u) -ne 0 ]] && die "You must run this action as root or with 'sudo'."
    [[ $NO_PREFIX == true ]] && SNAP_NAME="${SNAP_DATE}"
    [[ $USE_GIVEN_NAME == true ]] && LAST_SNAP="$SNAP_NAME"

    # Create snapshot entry
    echo -e "\nCreating ZFS snapshot '$LAST_SNAP'...\n"
    if [[ $DRY_RUN == true ]]; then
        if [[ $RECURSIVE_MODE == true ]]; then
            echo -e "[DRY-RUN] Should run: zfs snapshot -r $POOL_NAME@$SNAP_NAME\n"
        else
            echo -e "[DRY-RUN] Should run: zfs snapshot $POOL_NAME@$SNAP_NAME\n"
        fi
    else
        if [[ $RECURSIVE_MODE == true ]]; then
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DEBUG] Running: zfs snapshot -r $POOL_NAME@$SNAP_NAME\n"
            fi
            zfs snapshot -r "$POOL_NAME@$SNAP_NAME" || die "Could not create '$SNAP_NAME' recursively."
            RET_CODE_CREATE=$?
        else
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DEBUG] Running: zfs snapshot $POOL_NAME@$SNAP_NAME\n"
            fi
            zfs snapshot "$POOL_NAME@$SNAP_NAME" || die "Could not create '$SNAP_NAME'."
            RET_CODE_CREATE=$?
        fi
    fi

    # Check result
    if [[ $DRY_RUN == false ]]; then
        if [[ $RET_CODE_CREATE -eq 0 ]]; then
            echo -e "\nSnapshot created.\n"
            zfs list -t snapshot | head -n1
            zfs list -t snapshot -H | grep "$SNAP_NAME"
        else
            die "Failed to create snapshot."
        fi
    fi
}
function zfs_send() {
    [[ $USE_GIVEN_NAME == true ]] && LAST_SNAP="$SNAP_NAME"
    [[ $SAVE_ALL == false && $SNAP_COUNT -gt 2 ]] && FIRST_SNAP="$PREV_SNAP"
    [[ $SAVE_ALL == true ]] && OUTPUT_NAME="${POOL_NAME}@combined.snap"
    [[ $SAVE_ALL == true && $INCREMENTAL_MODE == true ]] && OUTPUT_NAME="${OUTPUT_NAME/combined/combined.incremental}"
    [[ $SAVE_ALL == true && $INCREMENTAL_MODE == false ]] && OUTPUT_NAME="${OUTPUT_NAME/combined/combined.full}"
    [[ -z $OUTPUT_NAME ]] && OUTPUT_NAME="${LAST_SNAP}.snap"

    # TODO
    # [[ $USE_COMPRESSION == true && $COMPRESS_WITH_GZIP == true ]] && OUTPUT_NAME="${OUTPUT_NAME}.gz"
    # [[ $USE_COMPRESSION == true && $COMPRESS_WITH_XZ == true ]] && OUTPUT_NAME="${OUTPUT_NAME}.xz"

    # Sanity check
    [[ ! -d "$SNAP_MOUNT" ]] && die "Missing remote snapshot mountpoint, please use '--mountpoint=' to specify it."

    # Create snapshot folder
    if [[ ! -d "$SNAP_FOLDER" ]]; then
        echo -e "\nCreating ZFS snapshot folder...\n"
        mkdir -pv "$SNAP_FOLDER"
    fi

    # Create snapshot file
    echo -e "\nCreating ZFS snapshot file '$OUTPUT_NAME'...\n"
    if [[ $DRY_RUN == true ]]; then
        if [[ $RECURSIVE_MODE == true ]]; then
            if [[ $INCREMENTAL_MODE == true ]]; then
                if [[ $DEBUG_MODE == true ]]; then
                    echo -e "[DRY-RUN] Running: zfs send -I $FIRST_SNAP $LAST_SNAP -R -w -v -n\n"
                fi
                zfs send -I "$FIRST_SNAP" "$LAST_SNAP" -R -w -v -n
            else
                if [[ $DEBUG_MODE == true ]]; then
                    echo -e "[DRY-RUN] Running: zfs send $LAST_SNAP -R -w -v -n\n"
                fi
                zfs send "$LAST_SNAP" -R -w -v -n
            fi
        else
            if [[ $INCREMENTAL_MODE == true ]]; then
                if [[ $DEBUG_MODE == true ]]; then
                    echo -e "[DRY-RUN] Running: zfs send -I $FIRST_SNAP $LAST_SNAP -w -v -n\n"
                fi
                zfs send -I "$FIRST_SNAP" "$LAST_SNAP" -w -v -n
            else
                if [[ $DEBUG_MODE == true ]]; then
                    echo -e "[DRY-RUN] Running: zfs send $LAST_SNAP -w -v -n\n"
                fi
                zfs send "$LAST_SNAP" -w -v -n
            fi
        fi
    else
        if [[ $RECURSIVE_MODE == true ]]; then
            if [[ $INCREMENTAL_MODE == true ]]; then
                if [[ $DEBUG_MODE == true ]]; then
                    echo -e "[DEBUG] Running: zfs send -I $FIRST_SNAP $LAST_SNAP -R -w -v > $SNAP_FOLDER/$OUTPUT_NAME\n"
                fi
                zfs send -I "$FIRST_SNAP" "$LAST_SNAP" -R -w -v > "$SNAP_FOLDER"/"$OUTPUT_NAME"
                RET_CODE_SEND=$?
            else
                if [[ $DEBUG_MODE == true ]]; then
                    echo -e "[DEBUG] Running: zfs send $LAST_SNAP -R -w -v > $SNAP_FOLDER/$OUTPUT_NAME\n"
                fi
                zfs send "$LAST_SNAP" -R -w -v > "$SNAP_FOLDER"/"$OUTPUT_NAME" || die "Could not send '$LAST_SNAP' recursively."
                RET_CODE_SEND=$?
            fi
        else
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DEBUG] Running: zfs send $LAST_SNAP -w -v > $SNAP_FOLDER/$OUTPUT_NAME\n"
            fi
            zfs send "$LAST_SNAP" -w -v > "$SNAP_FOLDER"/"$OUTPUT_NAME" || die "Could not send '$LAST_SNAP'."
            RET_CODE_SEND=$?
        fi

        # Check result
        if [[ $DRY_RUN == false ]]; then
            if [[ $RET_CODE_SEND -eq 0 ]]; then
                echo -e "\nSnapshot file created.\n"
                ls -halF "$SNAP_FOLDER"
            else
                die "Failed to create snapshot file."
            fi
        fi
    fi
}
function zfs_delete() {
    [[ $(id -u) -ne 0 ]] && die "You must run this action as root or with 'sudo'."
    [[ $USE_GIVEN_NAME == true ]] && LAST_SNAP="${POOL_NAME}@${SNAP_NAME}"

    echo -e "\nDeleting ZFS snapshot '$LAST_SNAP'...\n"
    if [[ $DRY_RUN == true ]]; then
        if [[ $RECURSIVE_MODE == true ]]; then
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DRY-RUN] Running: zfs destroy -R -v -n $LAST_SNAP\n"
            fi
            zfs destroy -R -v -n "$LAST_SNAP"
        else
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DRY-RUN] Running: zfs destroy -v -n $LAST_SNAP\n"
            fi
            zfs destroy -v -n "$LAST_SNAP"
        fi
    else
        if [[ $RECURSIVE_MODE == true ]]; then
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DEBUG] Running: zfs destroy -R -v $LAST_SNAP\n"
            fi
            zfs destroy -R -v "$LAST_SNAP" || die "Unable to remove '$LAST_SNAP' recursively."
            RET_CODE_DEL=$?
        else
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DEBUG] Running: zfs destroy -v $LAST_SNAP\n"
            fi
            zfs destroy -v "$LAST_SNAP" || die "Unable to remove '$LAST_SNAP'."
            RET_CODE_DEL=$?
        fi

        # Check result
        if [[ $DRY_RUN == false ]]; then
            if [[ $RET_CODE_DEL -eq 0 ]]; then
                echo -e "\nSnapshot deleted.\n"
                zfs list -t snapshot | head -n1
                zfs list -t snapshot -H | grep "$SNAP_NAME"
            else
                die "Failed to delete snapshot."
            fi
        fi
    fi
}
function zfs_dump() {
    [[ $USE_GIVEN_NAME == true ]] && LAST_SNAP="${POOL_NAME}@${SNAP_NAME}.snap" || LAST_SNAP="${LAST_SNAP}.snap"

    # Sanity check
    [[ ! -d "$SNAP_MOUNT" ]] && die "Missing remote snapshot mountpoint, please use '--mountpoint=' to specify it."

    echo -e "\nDumping ZFS snapshot details from '$LAST_SNAP'...\n"
    if [[ -f "$SNAP_FOLDER/$LAST_SNAP" ]]; then
        if [[ $DRY_RUN == true ]]; then
            echo -e "[DRY-RUN] Should run: zstream dump $SNAP_FOLDER/$LAST_SNAP\n"
        else
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DEBUG] Running: zstream dump $SNAP_FOLDER/$LAST_SNAP\n"
            fi
            zstream dump "$SNAP_FOLDER"/"$LAST_SNAP" || die "Could not dump '$SNAP_FOLDER/$LAST_SNAP'."
            echo -e "\nDone.\n"
        fi
    else
        die "Could not find '$LAST_SNAP' in '$SNAP_FOLDER'."
    fi
}
function zfs_diff() {
    [[ $USE_GIVEN_NAME == true ]] && LAST_SNAP="${SNAP_NAME}"

    # Fish command
    # for D in $(zfs list -t snapshot | grep "$(for S in $(zfs list -H | awk '{ print $1 }') ; zfs get all -H $S | grep -v 'none' | grep mountpoint | awk '{ print $1 }'; end)" | grep "$(zfs list -t snapshot -H | grep -v "/" | tail -n1 | awk '{ print $1 }' | sed -e 's/zpcachyos@//')" | awk '{ print $1 }') ; sudo zfs diff -F $D ; end > /tmp/zfs-diff.log && less /tmp/zfs-diff.log
    # Bash converted command
    # for D in $(zfs list -t snapshot | grep "$(for S in $(zfs list -H | awk '{ print $1 }') ; do zfs get all -H "$S" | grep -v 'none' | grep mountpoint | awk '{ print $1 }'; done)" | grep "$(zfs list -t snapshot -H | grep -v "/" | tail -n1 | awk '{ print $1 }' | sed -e 's/zpcachyos@//')" | awk '{ print $1 }') ; do sudo zfs diff -F "$D" ; done > /tmp/zfs-diff.log && less /tmp/zfs-diff.log
    
    local ZFS_DIFF_CMD
    local DATASETS
    local MOUNTED_SNAPSHOTS

    mapfile -t DATASETS < <(zfs list -H | awk '{ print $1 }')
    MOUNTED_SNAPSHOTS=$(zfs list -t snapshot | grep "$(for S in "${DATASETS[@]}" ; do zfs get all -H "$S" | grep -v 'none' | grep mountpoint | awk '{ print $1 }'; done)" | grep "${LAST_SNAP//$POOL_NAME@/}" | awk '{ print $1 }')

    # The command below is awful but is the most faster
    # ZFS_DIFF_CMD="for D in $(zfs list -t snapshot | grep "$(for S in $(zfs list -H | awk '{ print $1 }') ; do zfs get all -H "$S" | grep -v 'none' | grep mountpoint | awk '{ print $1 }'; done)" | grep "$(zfs list -t snapshot -H | grep -v "/" | tail -n1 | awk '{ print $1 }' | sed -e 's/'"$POOL_NAME"'@//')" | awk '{ print $1 }') ; do sudo zfs diff -F \$D ; done > /tmp/zfs-diff.log && less /tmp/zfs-diff.log"
    # ZFS_DIFF_CMD="for D in $(zfs list -t snapshot | grep "$(for S in $(zfs list -H | awk '{ print $1 }') ; do zfs get all -H "$S" | grep -v 'none' | grep mountpoint | awk '{ print $1 }'; done)" | grep "${LAST_SNAP//$POOL_NAME@/}" | awk '{ print $1 }') ; do sudo zfs diff -F \$D ; done > /tmp/zfs-diff.log && less /tmp/zfs-diff.log"

    # Improved command but it might be a little bit slower
    ZFS_DIFF_CMD="for D in $MOUNTED_SNAPSHOTS ; do sudo zfs diff -F \$D ; done"

    if [[ $DRY_RUN == true ]]; then
        echo -e "[DRY-RUN] Should run:\n$ZFS_DIFF_CMD\n"
    else
        if [[ $DEBUG_MODE == true ]]; then
            echo -e "[DEBUG] Running:\n$ZFS_DIFF_CMD\n"
        fi
        # shellcheck disable=SC2086
        eval $ZFS_DIFF_CMD > /tmp/zfs-diff.log && \
            sort --parallel="$(nproc)" /tmp/zfs-diff.log -o /tmp/zfs-diff-sorted.log && \
            less /tmp/zfs-diff-sorted.log
    fi
}
function init_snap_mgr() {
    print_header
    case $ZFS_ACTION in
        "help") NO_HEADER=true ; show_usage ;;
        "list") zfs_list ;;
        "create") zfs_create ;;
        "send") zfs_send ;;
        "delete") zfs_delete ;;
        "dump") zfs_dump ;;
        "diff") zfs_diff ;;
        "history") zpool_history ;;
    esac
}

# Checks
[[ $# -eq 0 ]] && show_usage

# Arguments
INDEX=0
for ARG in "$@"; do
    if [[ $DEBUG_MODE == true ]]; then
        echo "Arg $((INDEX++)): $ARG"
    fi

    case $ARG in
        "help"|"list"|"create"|"send"|"delete"|"dump"|"diff"|"history")
            ZFS_ACTION="$ARG"
        ;;
        "-h"|"--help") show_usage ;;
        "-v"|"--version") show_version ;;
        "-d"|"--debug") DEBUG_MODE=true ;;
        "-n"|"--dry-run") DRY_RUN=true ;;
        "-r"|"--recursive") RECURSIVE_MODE=true ;;
        "-i"|"--incremental") INCREMENTAL_MODE=true ;;
        "--all") SAVE_ALL=true ;;
        "--no-header") NO_HEADER=true ;;
        "--no-prefix") NO_PREFIX=true ;;
        "--mountpoint="*)
            [[ -z "${ARG/--mountpoint=/}" ]] && die "Missing remote snapshot mountpoint."
            [[ -n "${ARG/--mountpoint=/}" ]] && SNAP_FOLDER="${ARG/--mountpoint=/}/$HOST_NAME"
        ;;
        "--name="*)
            [[ -z "${ARG/--name=/}" ]] && die "Missing snapshot name."

            USE_GIVEN_NAME=true
            SNAP_PREFIX="${ARG/--name=/}"
            if [[ $NO_PREFIX == false ]]; then
                SNAP_NAME="${SNAP_PREFIX}-${SNAP_DATE}"
            else
                SNAP_NAME="${SNAP_PREFIX}"
            fi
        ;;
        "--compress="*)
            [[ -z "${ARG/--compress=/}" ]] && die "Missing compression format."
            [[ -n "${ARG/--compress=/}" ]] && USE_COMPRESSION=true
            [[ "${ARG/--compress=/}" == "gzip" ]] && COMPRESS_WITH_GZIP=true
            [[ "${ARG/--compress=/}" == "xz" ]] && COMPRESS_WITH_XZ=true
        ;;
        *)
            die "Unsupported argument given: $ARG"
        ;;
    esac
done

# Main
init_snap_mgr
