#!/usr/bin/env zsh

battery () {
    declare -r state=$(upower -i /org/freedesktop/UPower/devices/DisplayDevice | grep -P "(?<=state:)" | grep -oP "charging|discharging|fully-charged")
}
