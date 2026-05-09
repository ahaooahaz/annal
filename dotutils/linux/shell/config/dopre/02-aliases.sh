alias l='ls -CF'
alias ll='ls -alF'
alias la='ls -A'
alias ls='ls --color=auto'
alias lexa='exa -lh --group-directories-first --git --time-style=long-iso'

alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

alias say=spd-say
alias t=tmux

alias kubectx='kubectl config use-context '

alias open='xdg-open'
alias grep='grep --color=auto'
alias watch='watch ' # enable alias commands
alias sudo='sudo '   # enable alias commands
# cale min max mean.
alias mmm='awk '\''
BEGIN{max=-1e10;min=1e10;sum=0;n=0}
{sum+=$1;n+=1;if($1>max)max=$1;if($1<min)min=$1}
END{print "Max:", max, "Min:", min, "Mean:", (n>2)?(sum-min-max)/(n-2):sum/n}'\'

alias clear='printf "\033[H\033[J"'
