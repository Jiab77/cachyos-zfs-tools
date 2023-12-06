#!/usr/bin/env bash

# Basic updater script for CachyOS ZFS tools
# Made by Jiab77 - 2023
#
# Thanks to vnepogodin for the inspiration of the 'die' method :)
#
# Version 0.0.3

# Options
set +o xtrace

# Config
PROJECT_NAME="CachyOS ZFS tools/scripts"

# Functions
function get_version() {
    grep -i 'version' "$0" | awk '{ print $3 }' | head -n1
}
function die() {
    echo -e "\nError: $*\n" >&2
    exit 255
}

# Header
echo -e "\nSimple $PROJECT_NAME updater - v$(get_version)\n"

# Usage
[[ $1 == "-h" && $1 == "--help" ]] && echo -e "\nUsage: $(basename "$0") -- Update $PROJECT_NAME.\n" && exit 0

# Checks
[[ $(id -u) -ne 0 ]] && die "You must run this script as root or with 'sudo'."

# Main
bash ./uninstall.sh --no-header
bash ./install.sh --no-header