#!/bin/bash

cpu_count=`adb shell cat /sys/devices/system/cpu/present`
cpu_count=${cpu_count//"0-"/}
cpu_count=$((cpu_count + 1))
for i in $(seq 0 $((cpu_count - 1)))
do
    cpuinfo_cur_freq=$(adb shell "cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_cur_freq")
    cpuinfo_max_freq=$(adb shell "cat /sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq")
    adb shell "echo performance > /sys/devices/system/cpu/cpu$i/cpufreq/scaling_governor"
    adb shell "echo $cpuinfo_max_freq > /sys/devices/system/cpu/cpu$i/cpufreq/scaling_min_freq"
    adb shell "echo $cpuinfo_max_freq > /sys/devices/system/cpu/cpu$i/cpufreq/scaling_max_freq"
done
android_get_cpu_freq.sh
