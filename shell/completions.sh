# sre-toolkit shell completions for installed infra CLI tools.
#
# This file is sourced from your shell rc file by
# scripts/setup-shell-aliases.sh, right after shell/aliases.sh. It loads
# each tool's own official completion script - nothing here is a custom
# alias. A tool that isn't installed, or doesn't support the current
# shell, is silently skipped.

if [ -n "${ZSH_VERSION:-}" ]; then
  autoload -Uz compinit && compinit -C
  _sre_toolkit_completion_shell=zsh
elif [ -n "${BASH_VERSION:-}" ]; then
  _sre_toolkit_completion_shell=bash
fi

if [ -n "${_sre_toolkit_completion_shell:-}" ]; then
  _sre_toolkit_load_completion() {
    local script
    script="$("$@" 2>/dev/null)" || return 0
    [ -n "$script" ] || return 0
    eval "$script"
  }

  command -v kubectl  >/dev/null 2>&1 && _sre_toolkit_load_completion kubectl completion "$_sre_toolkit_completion_shell"
  command -v minikube >/dev/null 2>&1 && _sre_toolkit_load_completion minikube completion "$_sre_toolkit_completion_shell"
  command -v gh       >/dev/null 2>&1 && _sre_toolkit_load_completion gh completion -s "$_sre_toolkit_completion_shell"
  command -v docker   >/dev/null 2>&1 && _sre_toolkit_load_completion docker completion "$_sre_toolkit_completion_shell"

  unset -f _sre_toolkit_load_completion
fi
unset _sre_toolkit_completion_shell
