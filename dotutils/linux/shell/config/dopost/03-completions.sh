# completion.
apps=(kubectl helm)
for app in ${apps}; do
    if [ $(
        type ${app} >/dev/null 2>&1
        echo $?
    ) -eq 0 ]; then
        source <(${app} completion ${CURRSHELL})
    fi
done

apps=(stern)
for app in ${apps}; do
    if [ $(
        type ${app} >/dev/null 2>&1
        echo $?
    ) -eq 0 ]; then
        source <(${app} --completion ${CURRSHELL})
    fi
done
