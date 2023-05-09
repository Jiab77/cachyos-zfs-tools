#!/usr/bin/env bash
# shellcheck disable=SC2034

# Simple CachyOS ZFS snapshot manager
# Made by Jiab77 - 2023
#
# TODO:
# - Improve snapshots folder handling
# - Implement rollback feature
# - Implement compressed stream file output
# - Implement SSH connection
#
# Version 0.0.0

# Options
set +o xtrace

# Config
DEBUG_MODE=false
DRY_RUN=false
RECURSIVE_MODE=false
INCREMENTAL_MODE=false
NO_PREFIX=false
USE_GIVEN_NAME=false
USE_COMPRESSION=false
COMPRESS_WITH_GZIP=false
COMPRESS_WITH_XZ=false
SAVE_ALL=false
POOL_NAME=$(zpool list -H | awk '{ print $1 }')
FIRST_SNAP=$(zfs list -t snapshot -H | head -n1 | awk '{ print $1 }')
PREV_SNAP=$(zfs list -t snapshot -H | grep -v "/" | tail -n2 | head -n1 | awk '{ print $1 }')
LAST_SNAP=$(zfs list -t snapshot -H | grep -v "/" | tail -n1 | awk '{ print $1 }')
SNAP_COUNT=$(zfs list -t snapshot -H | grep -cv "/")
SNAP_BASE=$(grep "$(id -un 1000)" /etc/passwd | head -n1 | sed -e 's/:/ /g' | awk '{ print $6 }')
SNAP_FOLDER="$SNAP_BASE/Data/Snapshots/CachyOS"
SNAP_PREFIX="initial"
SNAP_DATE=$(date "+%Y%m%d%H%M%S")
SNAP_NAME="${SNAP_PREFIX}-${SNAP_DATE}"

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
    echo -e "list\t\t\t\t\tList existing snapshots."
    echo -e "create\t\t\t\t\tCreate new snapshot."
    echo -e "send\t\t\t\t\tSend snapshot to remote file. (Insite a remotely mapped folder only)"
    echo -e "delete\t\t\t\t\tDelete given snapshot."
    echo -e "\nOptions:\n"
    echo -e "-h|--help\t\t\t\tShow this message."
    echo -e "-v|--version\t\t\t\tShow script version."
    echo -e "-d|--debug\t\t\t\tEnable debug mode."
    echo -e "-n|--dry-run\t\t\t\tSimulate requested actions, don't execute them."
    echo -e "-r|--recursive\t\t\t\tRun <ACTION> recursively."
    echo -e "-i|--incremental\t\t\tMake incremental snapshot files."
    echo -e "--no-prefix\t\t\t\tUse date only as snapshot name."
    echo -e "--name=<snapshot-name>\t\t\tSet snapshot name instead of default one."
    echo -e "--compress=<gzip,xz>\t\t\tCompress snapshot file in given format."
    echo -e "--output=</path/to/snapshot/file>\tCompress snapshot file in given format."
    echo -e "\nDisclaimer:\n\n /!\ This script is still experimental so use it with caution. /!\ \n"
    exit
}
function zfs_list() {
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
    [[ $(id -u) -ne 0 ]] && echo -e "\nError: You must run this action as root or with 'sudo'.\n" && exit 1
    [[ $NO_PREFIX == true ]] && SNAP_NAME="${SNAP_DATE}"
    [[ $USE_GIVEN_NAME == true ]] && LAST_SNAP="$SNAP_NAME"

    # Create snapshot entry
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
            zfs snapshot -r "$POOL_NAME@$SNAP_NAME"
            RET_CODE_CREATE=$?
        else
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DEBUG] Running: zfs snapshot $POOL_NAME@$SNAP_NAME\n"
            fi
            zfs snapshot "$POOL_NAME@$SNAP_NAME"
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
            echo -e "\nFailed to create snapshot.\n"
            exit 1
        fi
    fi
}
function zfs_send() {
    [[ $NO_PREFIX == true ]] && SNAP_NAME="${SNAP_DATE}"
    [[ $USE_GIVEN_NAME == true ]] && LAST_SNAP="$SNAP_NAME"
    [[ $SAVE_ALL == false && $SNAP_COUNT -gt 2 ]] && FIRST_SNAP="$PREV_SNAP"
    [[ $SAVE_ALL == true && -z "$OUTPUT_NAME" ]] && OUTPUT_NAME="${POOL_NAME}@combined.snap"
    [[ -z "$OUTPUT_NAME" ]] && OUTPUT_NAME="${LAST_SNAP}.snap"

    # Create snapshot file
    if [[ $DRY_RUN == true ]]; then
        if [[ $RECURSIVE_MODE == true ]]; then
            if [[ $INCREMENTAL_MODE == true ]]; then
                if [[ $DEBUG_MODE == true ]]; then
                    echo -e "[DEBUG] Running: zfs send -I $FIRST_SNAP $LAST_SNAP -R -w -v -n\n"
                fi
                zfs send -I "$FIRST_SNAP" "$LAST_SNAP" -R -w -v -n
            else
                if [[ $DEBUG_MODE == true ]]; then
                    echo -e "[DEBUG] Running: zfs send $LAST_SNAP -R -w -v -n\n"
                fi
                zfs send "$LAST_SNAP" -R -w -v -n
            fi
        else
            if [[ $INCREMENTAL_MODE == true ]]; then
                if [[ $DEBUG_MODE == true ]]; then
                    echo -e "[DEBUG] Running: zfs send -I $FIRST_SNAP $LAST_SNAP -w -v -n\n"
                fi
                zfs send -I "$FIRST_SNAP" "$LAST_SNAP" -w -v -n
            else
                if [[ $DEBUG_MODE == true ]]; then
                    echo -e "[DEBUG] Running: zfs send $LAST_SNAP -w -v -n\n"
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
                zfs send "$LAST_SNAP" -R -w -v > "$SNAP_FOLDER"/"$OUTPUT_NAME"
                RET_CODE_SEND=$?
            fi
        else
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DEBUG] Running: zfs send $LAST_SNAP -w -v > $SNAP_FOLDER/$OUTPUT_NAME\n"
            fi
            zfs send "$LAST_SNAP" -w -v > "$SNAP_FOLDER"/"$OUTPUT_NAME"
            RET_CODE_SEND=$?
        fi

        # Check result
        if [[ $DRY_RUN == false ]]; then
            if [[ $RET_CODE_SEND -eq 0 ]]; then
                echo -e "\nSnapshot file created.\n"
                ls -halF "$SNAP_FOLDER"
            else
                echo -e "\nFailed to create snapshot file.\n"
                exit 2
            fi
        fi
    fi
}
function zfs_delete() {
    [[ $(id -u) -ne 0 ]] && echo -e "\nError: You must run this action as root or with 'sudo'.\n" && exit 1
    [[ $USE_GIVEN_NAME == true ]] && LAST_SNAP="${POOL_NAME}@${SNAP_NAME}"

    if [[ $DRY_RUN == true ]]; then
        if [[ $RECURSIVE_MODE == true ]]; then
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DEBUG] Running: zfs destroy -R -v -n $LAST_SNAP\n"
            fi
            zfs destroy -R -v -n "$LAST_SNAP"
        else
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DEBUG] Running: zfs destroy -v -n $LAST_SNAP\n"
            fi
            zfs destroy -v -n "$LAST_SNAP"
        fi
    else
        if [[ $RECURSIVE_MODE == true ]]; then
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DEBUG] Running: zfs destroy -R -v $LAST_SNAP\n"
            fi
            zfs destroy -R -v "$LAST_SNAP"
            RET_CODE_DEL=$?
        else
            if [[ $DEBUG_MODE == true ]]; then
                echo -e "[DEBUG] Running: zfs destroy -v $LAST_SNAP\n"
            fi
            zfs destroy -v "$LAST_SNAP"
            RET_CODE_DEL=$?
        fi

        # Check result
        if [[ $DRY_RUN == false ]]; then
            if [[ $RET_CODE_DEL -eq 0 ]]; then
                echo -e "\nSnapshot deleted.\n"
                zfs list -t snapshot | head -n1
                zfs list -t snapshot -H | grep "$SNAP_NAME"
            else
                echo -e "\nFailed to delete snapshot.\n"
                exit 3
            fi
        fi
    fi
}
function zfs_dump() {
    [[ -z "$OUTPUT_NAME" ]] && OUTPUT_NAME="${LAST_SNAP}.snap"

    if [[ $DRY_RUN == true ]]; then
        echo -e "[DRY-RUN] Should run: zstream dump $SNAP_FOLDER/$OUTPUT_NAME\n"
    else
        if [[ $DEBUG_MODE == true ]]; then
            echo -e "[DEBUG] Running: zstream dump $SNAP_FOLDER/$OUTPUT_NAME\n"
        fi
        zstream dump "$SNAP_FOLDER"/"$OUTPUT_NAME"
    fi
}
function init_snap_mgr() {
    case $ZFS_ACTION in
        "list") zfs_list ;;
        "create") zfs_create ;;
        "send") zfs_send ;;
        "delete") zfs_delete ;;
        "dump") zfs_dump ;;
    esac
}

# Header
echo -e "\nSimple CachyOS ZFS snapshot manager"

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
        "list")
            ZFS_ACTION="list"
        ;;
        "create")
            ZFS_ACTION="create"
        ;;
        "send")
            ZFS_ACTION="send"
        ;;
        "delete")
            ZFS_ACTION="delete"
        ;;
        "dump")
            ZFS_ACTION="dump"
        ;;
        "-h"|"--help") show_usage ;;
        "-v"|"--version") show_version ;;
        "-n"|"--dry-run") DRY_RUN=true ;;
        "-d"|"--debug") DEBUG_MODE=true ;;
        "-r"|"--recursive") RECURSIVE_MODE=true ;;
        "-i"|"--incremental") INCREMENTAL_MODE=true ;;
        "--all") SAVE_ALL=true ;;
        "--no-prefix") NO_PREFIX=true ;;
        "--name="*)
            [[ -z "${ARG/--name=/}" ]] && echo -e "\nError: Missing snapshot name.\n" && exit 1

            USE_GIVEN_NAME=true
            SNAP_PREFIX="${ARG/--name=/}"
            if [[ $NO_PREFIX == false ]]; then
                SNAP_NAME="${SNAP_PREFIX}-${SNAP_DATE}"
            else
                SNAP_NAME="${SNAP_PREFIX}"
            fi
        ;;
        "--compress="*)
            [[ -z "${ARG/--compress=/}" ]] && echo -e "\nError: Missing compression format.\n" && exit 1
            [[ -n "${ARG/--compress=/}" ]] && USE_COMPRESSION=true
            [[ "${ARG/--compress=/}" == "gzip" ]] && COMPRESS_WITH_GZIP=true
            [[ "${ARG/--compress=/}" == "xz" ]] && COMPRESS_WITH_XZ=true
        ;;
        "--output="*)
            [[ -z "${ARG/--output=/}" ]] && echo -e "\nError: Missing output file.\n" && exit 1
            [[ -n "${ARG/--output=/}" ]] && OUTPUT_NAME="${ARG/--output=/}"
            [[ $USE_COMPRESSION == true && $COMPRESS_WITH_GZIP == true ]] && OUTPUT_NAME="${OUTPUT_NAME}.gz"
            [[ $USE_COMPRESSION == true && $COMPRESS_WITH_XZ == true ]] && OUTPUT_NAME="${OUTPUT_NAME}.xz"
        ;;
        *)
            echo -e "\nError: Unsupported argument given: $ARG"
            exit 4
        ;;
    esac
done

# Main
init_snap_mgr
