#!/bin/bash

# set -x

notifysend_sh=${ANNAL_ROOT}/plugins/notify-send.sh/notify-send.sh
icon=${ANNAL_ROOT}/icons/icon.svg

function usage() {
cat << USAGE
usage: notify-send.sh [OPTION] [PARAMS]
        -ti|--title         title.
        -d|--desp           desp.
        -t|--timeout        timeout.

        -h|--help   show help.
USAGE
}

# $1 title, $2 desp, $3 timeout
function notify() {
    ${notifysend_sh} --print-id -u critical -i ${icon} "$1" "$2" | xargs -I {} bash -c "sleep ${timeout} && ${notifysend_sh} --close={}" &
}

while [ $# -ne 0 ]
do
    echo \"$2\"
    key=$1
    case ${key} in
        -ti|--title)
            title=$2
            shift
            shift
            ;;
        -d|--desp)
            desp=$2
            shift
            shift
            ;;
        -t|--timeout)
            timeout=$2
            shift
            shift
            ;;
        *)
            usage
            return 1
    esac
done
expr $timeout "+" 10 &> /dev/null
if [ $? -ne 0 ];then
    timeout=3
fi

notify ${title} ${desp} ${timeout}

