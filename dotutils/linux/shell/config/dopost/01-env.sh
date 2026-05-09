include -f "${HOME}/.venv/bin/activate"
include -f "${HOME}/.inti_shrc"

hash -d config=$XDG_CONFIG_HOME
hash -d cache=$XDG_CACHE_HOME
hash -d data=$XDG_DATA_HOME
# fzf
export FZF_DEFAULT_OPTS="
--color=dark
--color=fg:#707a8c,bg:-1,hl:#3e9831,fg+:#cbccc6,bg+:#434c5e,hl+:#5fff87
--color=info:#af87ff,prompt:#5fff87,pointer:#ff87d7,marker:#ff87d7,spinner:#ff87d7
--height 60%
--layout reverse
--sort
--preview '
if [ -d {} ]; then
    tree -N -C {} | head -500
elif file --mime {} | grep -q image; then
    mcat {} --ascii
else
    bat --style=numbers --color=always {} 2>/dev/null \
    || highlight -O ansi -l {} 2>/dev/null \
    || cat {} | head -500
fi
'
--preview-window right:50%:wrap
--bind '?:toggle-preview'
--border
--cycle
"
export FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND
export FZF_CTRL_T_OPTS=$FZF_DEFAULT_OPTS
export FZF_CTRL_R_OPTS="
--layout=reverse
--sort
--exact
--preview 'echo {}'
--preview-window down:3:wrap
--bind '?:toggle-preview'
--border
--cycle
--bind=tab:down
--bind=btab:up
"
# bat
export BAT_THEME='OneHalfDark'
# man
export HISTFILE=~/.${CURRSHELL}_history
export HISTSIZE=1000000  # number of commands that are loaded
export SAVEHIST=1000000  # number of commands that are stored
# mcat
# NOTE: if terminal is not `kitty` need to change it.
export MCAT_ENCODER=kitty

export GPG_TTY=$(tty)
