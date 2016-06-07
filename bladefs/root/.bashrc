# ~/.bashrc: executed by bash(1) for non-login shells.

export PS1='\h:\w\$ '
umask 022

alias screen='screen -e^Oa'
alias ls='/bin/ls -CF'
alias ll='ls -l'
alias la='ls -a'
alias ps='~/bin/ps'
alias psthread="/bin/ps -AeF -T"
alias grep="grep --color"
alias rgrep="rgrep --color"
alias less="less -S"

EDITOR="emacs -nw"
PATH=$PATH:~/bin

export EDITOR PATH
unset LANG
unset LANGUAGE
