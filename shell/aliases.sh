# sre-toolkit shell aliases.
#
# This file is sourced from your shell rc file by scripts/setup-shell-aliases.sh.
# It is meant to stay POSIX-ish so the same file works under bash and zsh, on
# both Linux and macOS. Edit it freely - changes take effect in new shells
# without re-running the installer.

# --- git history graph -------------------------------------------------------
# Note: these names can collide with framework-provided aliases (oh-my-zsh's
# git plugin defines glg, for example). Because this file is sourced at the end
# of your rc file it wins; rename below if you prefer the framework's version.

# Current branch only - the everyday view.
alias glg='git log --graph --oneline --decorate'

# All refs, including remote-tracking branches. Wide on busy repos.
alias glga='git log --graph --oneline --decorate --all'

# Same as glga, with relative dates and authors.
alias glgp="git log --graph --all --decorate --abbrev-commit --format=tformat:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)'"

# --- docker ------------------------------------------------------------------
# Docker 29's default `docker images` view dropped the build/creation
# timestamp; this puts it back.
alias dimg="docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}'"
