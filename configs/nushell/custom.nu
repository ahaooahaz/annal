alias vim = nvim
alias vi = nvim
alias grep = grep --color=auto
alias cat = open --raw
alias adb_get_cpu_freq = adb shell '
cpu_range=$(cat /sys/devices/system/cpu/present)
cpu_max=${cpu_range#0-}
cpu_count=$((cpu_max + 1))
for i in $(seq 0 $((cpu_count - 1))); do
    prefix=/sys/devices/system/cpu/cpu$i/cpufreq
    scaling_governor=$(cat $prefix/scaling_governor 2>/dev/null)
    cpuinfo_cur_freq=$(cat $prefix/cpuinfo_cur_freq 2>/dev/null)
    cpuinfo_max_freq=$(cat $prefix/cpuinfo_max_freq 2>/dev/null)
    cpuinfo_min_freq=$(cat $prefix/cpuinfo_min_freq 2>/dev/null)
    scaling_cur_freq=$(cat $prefix/scaling_cur_freq 2>/dev/null)
    scaling_min_freq=$(cat $prefix/scaling_min_freq 2>/dev/null)
    scaling_max_freq=$(cat $prefix/scaling_max_freq 2>/dev/null)
    echo "cpu[$i]: l($scaling_governor) cpuinfo/scaling: cur_freq($cpuinfo_cur_freq/$scaling_cur_freq) min_freq($cpuinfo_min_freq/$scaling_min_freq) max_freq($cpuinfo_max_freq/$scaling_max_freq)"
done
echo "cpu_count: $cpu_count"
'

alias adb_performance_cpu_freq = do {
    adb shell '
    cpu_range=$(cat /sys/devices/system/cpu/present)
    cpu_max=${cpu_range#0-}
    cpu_count=$((cpu_max + 1))
    for i in $(seq 0 $((cpu_count - 1))); do
        prefix=/sys/devices/system/cpu/cpu$i/cpufreq
        cpuinfo_max_freq=$(cat $prefix/cpuinfo_max_freq 2>/dev/null)
        echo performance > $prefix/scaling_governor 2>/dev/null
        echo $cpuinfo_max_freq > $prefix/scaling_min_freq 2>/dev/null
        echo $cpuinfo_max_freq > $prefix/scaling_max_freq 2>/dev/null
    done
    '
    adb_get_cpu_freq
}
