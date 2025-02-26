#!/bin/bash

cpu_count=`adb shell cat /sys/devices/system/cpu/present`
cpu_count=${cpu_count//"0-"/}
cpu_count=$((cpu_count + 1))
for i in $(seq 0 $((cpu_count - 1)))
do
    scaling_governor=$(adb shell "cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor")
    cpuinfo_cur_freq=$(adb shell "cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_cur_freq")
    cpuinfo_max_freq=$(adb shell "cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq")
    cpuinfo_min_freq=$(adb shell "cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_min_freq")
    scaling_cur_freq=$(adb shell "cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_cur_freq")
    scaling_min_freq=$(adb shell "cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_min_freq")
    scaling_max_freq=$(adb shell "cat /sys/devices/system/cpu/cpu$i/cpufreq/scaling_max_freq")
    echo "cpu[$i]: \
l($scaling_governor) \
cpuinfo/scaling: cur_freq($cpuinfo_cur_freq/$scaling_cur_freq) \
min_freq($cpuinfo_min_freq/$scaling_min_freq) \
max_freq($cpuinfo_max_freq/$scaling_max_freq) \
"
done
echo "cpu_count: ${cpu_count}"
