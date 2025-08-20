#!/bin/bash
set -e

serial=
adbopt="adb"

function usage() {
    cat << EOF
usage: android_cpu_freq.sh [get_cpu_freq|set_cpu_freq] [OPTIONS]
    set_cpu_freq|get_cpu_freq
        -s              device serial number
        -L              lock cpu freq level: [performance], default: performance
EOF
}

function parse() {
    ARGS=$(getopt -o s:,L: -l serial: -- "$@")
    eval set -- "$ARGS"

    while [ $# -gt 0 ] ; do
        case "$1" in
            -s|--serial)
                serial=$2
                adbopt="adb -s $serial"
                shift 2
                ;;
            -L)
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done
}


function get_cpu_freq() {
    ${adbopt} exec-out '
        cpu_count=`cat /sys/devices/system/cpu/present`
        cpu_count=${cpu_count//"0-"/}
        cpu_count=$((cpu_count + 1))
        for i in $(seq 0 $((cpu_count - 1)))
        do
            scaling_governor=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor)
            cpuinfo_cur_freq=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_cur_freq)
            cpuinfo_max_freq=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq)
            cpuinfo_min_freq=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_min_freq)
            scaling_cur_freq=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq)
            scaling_min_freq=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_min_freq)
            scaling_max_freq=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_max_freq)
            echo "cpu[$i]: L($scaling_governor) \
cpuinfo/scaling: cur_freq($cpuinfo_cur_freq/$scaling_cur_freq) \
min_freq($cpuinfo_min_freq/$scaling_min_freq) \
max_freq($cpuinfo_max_freq/$scaling_max_freq)"
        done
        echo "cpu_count: ${cpu_count}"
'
}

function set_cpu_freq() {
    ${adbopt} exec-out '
        cpu_count=`cat /sys/devices/system/cpu/present`
        cpu_count=${cpu_count//"0-"/}
        cpu_count=$((cpu_count + 1))
        for i in $(seq 0 $((cpu_count - 1)))
        do
            cpuinfo_cur_freq=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_cur_freq)
            cpuinfo_max_freq=$(cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq)
            echo performance > /sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor
            echo $cpuinfo_max_freq > /sys/devices/system/cpu/cpu$i/cpufreq/scaling_min_freq
            echo $cpuinfo_max_freq > /sys/devices/system/cpu/cpu$i/cpufreq/scaling_max_freq
        done
'
    get_cpu_freq
}


if [ $# -eq 0 ]; then
    usage
    exit 1
fi

subcommand=(get_cpu_freq set_cpu_freq)
for i in "${subcommand[@]}"; do
    if [ $1 == $i ]; then
        command="$1"
        shift
        parse "$@"
        $command
        exit 0
    fi
done

echo "unknown subcommand: $1"
usage
exit 1
