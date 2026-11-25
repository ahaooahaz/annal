#!/usr/bin/env bash
# shellcheck shell=bash

if [[ "${CURROS}" == "Darwin" ]]; then
    alias make='gmake'
    alias timeout='gtimeout'
    alias ls='gls --color=auto'
    alias l='gls -CF --color=auto'
    alias ll='gls -alF --color=auto'
    alias la='gls -A --color=auto'
    alias open='open'
else
    alias ls='ls --color=auto'
    alias l='ls -CF'
    alias ll='ls -alF'
    alias la='ls -A'
    alias open='xdg-open'
fi

if command -v nvim &>/dev/null; then
    alias v=nvim
    alias vi=nvim
    alias vim=nvim
fi

alias lexa='exa -lh --group-directories-first --git --time-style=long-iso'

alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

alias say=spd-say
alias t=todo.sh

alias kubectx='kubectl config use-context '

alias watch='watch ' # enable alias commands
alias sudo='sudo '   # enable alias commands
function mmm() {
    awk '
    BEGIN{max=-1e10;min=1e10;sum=0;n=0}
    {sum+=$1;n+=1;if($1>max)max=$1;if($1<min)min=$1}
    END{print "Max:", max, "Min:", min, "Mean:", (n>2)?(sum-min-max)/(n-2):sum/n}
    ' "$@"
}

alias clear='printf "\033[H\033[J"'
