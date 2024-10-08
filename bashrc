# .bashrc

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]; then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi

# Add nvidia
PATH="$PATH:/usr/local/cuda/bin"
export PATH

# Add venv
source ~/venv/bin/activate


# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        if [ -f "$rc" ]; then
            . "$rc"
        fi
    done
fi
unset rc

export SSH_AUTH_SOCK=`gpgconf --list-dirs agent-ssh-socket`
gpgconf --launch gpg-agent
export GPG_TTY=`tty`
gpg-connect-agent updatestartuptty /bye > /dev/null
