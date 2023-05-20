#!/usr/bin/env bash

# Basic installer script for CachyOS ZFS tools
# Made by Jiab77 - 2023
#
# Thanks to vnepogodin for the inspiration of the 'die' method :)
#
# Version 0.0.0

# Options
set -o xtrace

# Config
PROJECT_NAME="CachyOS ZFS tools/scripts"
ALREADY_INSTALLED=false
INSTALL_PATH="/usr/local/bin"
INSTALL_SCRIPTS=(
    'zfs-snap-mgr.sh'
    'zfs-cos-recover.sh'
)

# Functions
function get_version() {
    grep -i 'version' "$0" | awk '{ print $3 }' | head -n1
}
function die() {
    echo -e "\nError: $*\n"
    exit 255
}

# Header
echo -e "\nSimple $PROJECT_NAME installer - v$(get_version)\n"

# Usage
[[ $1 == "-h" && $1 == "--help" ]] && echo -e "\nUsage: $(basename "$0") -- Install $PROJECT_NAME.\n" && exit 0

# Checks
[[ $(id -u) -ne 0 ]] && die "You must run this script as root or with 'sudo'."

# Main
echo -e "\nInstalling $PROJECT_NAME...\n"
for S in "${INSTALL_SCRIPTS[@]}"; do
    DEST="${S//.sh/}"
    if [[ ! -f "$INSTALL_PATH"/"$DEST" ]]; then
        install -T -v "$S" "$INSTALL_PATH"/"$DEST" || die "Could not install '$S' in '$INSTALL_PATH'."
        RET_CODE_INSTALL=$?
    else
        ALREADY_INSTALLED=true
    fi
done

# End
if [[ $ALREADY_INSTALLED == true ]]; then
    die "Already installed. Please run the 'uninstall.sh' script to remove installed $PROJECT_NAME."
else
    if [[ $RET_CODE_INSTALL -eq 0 ]]; then
        echo -e "\n$PROJECT_NAME installed.\n"
        exit 0
    else
        die "Could not install $PROJECT_NAME."
    fi
fi