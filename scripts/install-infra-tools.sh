#!/usr/bin/env bash
# Install the sre-toolkit infrastructure toolkit (macOS via Homebrew).
#
# Default behavior per tool:
#   - not installed  -> install the latest version
#   - already installed -> skip (no upgrade, no reinstall)
#
# Default is dry-run; pass --apply to actually install. Linux is a
# placeholder for now.
set -euo pipefail

APPLY=false

usage() {
  cat <<'USAGE'
Usage: install-infra-tools.sh [--apply]

  --apply    Actually install missing tools. Default is dry-run: report
             what would be installed and exit without changing anything.
  -h, --help Show this help.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

case "$(uname -s)" in
  Darwin) PLATFORM=macos ;;
  Linux)  PLATFORM=linux ;;
  *)      PLATFORM="$(uname -s)" ;;
esac

# --- Linux placeholder -------------------------------------------------------

if [ "$PLATFORM" = "linux" ]; then
  echo "Linux support is not implemented yet."
  echo "Tracking placeholder: add an apt/dnf-based installer here."
  exit 0
fi

if [ "$PLATFORM" != "macos" ]; then
  echo "error: unsupported platform '$PLATFORM' (macos and linux are supported)" >&2
  exit 1
fi

# --- macOS ---------------------------------------------------------------

if ! command -v brew >/dev/null 2>&1; then
  echo "error: Homebrew is required but not installed." >&2
  echo "Install it from https://brew.sh, then re-run this script." >&2
  exit 1
fi

# name -> human label, so status output stays readable
FORMULAE=(
  "kubernetes-cli:kubectl"
  "minikube:minikube"
  "gh:gh (GitHub CLI)"
  "cloudflared:cloudflared"
  "git-lfs:git-lfs"
  "tmux:tmux"
  "htop:htop"
  "neofetch:neofetch"
  "tree:tree"
  "ncdu:ncdu"
  "python@3.10:python@3.10"
  "python@3.11:python@3.11"
  "numpy:numpy"
  "scipy:scipy"
  "openblas:openblas"
  "lightgbm:lightgbm"
  "gcc:gcc"
  "gmp:gmp"
  "icu4c@78:icu4c"
  "openssl@1.1:openssl@1.1"
  "openssl@3:openssl@3"
)

CASKS=(
  "docker:Docker Desktop"
  "iterm2:iTerm2"
)

# oh-my-zsh + theme/plugins, matching the current ~/.zshrc setup:
#   ZSH_THEME="agnoster"
#   plugins=(git)
OMZ_DIR="$HOME/.oh-my-zsh"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
OMZ_INSTALL_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
DESIRED_ZSH_THEME='"agnoster"'
DESIRED_PLUGINS="(git)"

to_install_formulae=()
to_install_casks=()

echo "platform: $PLATFORM"
echo "mode:     $([ "$APPLY" = true ] && echo apply || echo dry-run)"
echo ""
echo "checking formulae..."
for entry in "${FORMULAE[@]}"; do
  name="${entry%%:*}"
  label="${entry#*:}"
  if brew list --formula --versions "$name" >/dev/null 2>&1; then
    echo "  [skip]    $label (already installed)"
  else
    echo "  [install] $label"
    to_install_formulae+=("$name")
  fi
done

echo ""
echo "checking casks..."
for entry in "${CASKS[@]}"; do
  name="${entry%%:*}"
  label="${entry#*:}"
  if brew list --cask --versions "$name" >/dev/null 2>&1; then
    echo "  [skip]    $label (already installed)"
  else
    echo "  [install] $label"
    to_install_casks+=("$name")
  fi
done

echo ""
echo "checking oh-my-zsh..."

omz_needs_install=false
if [ -d "$OMZ_DIR" ]; then
  echo "  [skip]    oh-my-zsh (already installed)"
else
  echo "  [install] oh-my-zsh"
  omz_needs_install=true
fi

theme_needs_update=false
plugins_needs_update=false
if [ -f "$ZSHRC" ]; then
  current_theme="$(grep -E '^ZSH_THEME=' "$ZSHRC" | tail -1 || true)"
  current_plugins="$(grep -E '^plugins=' "$ZSHRC" | tail -1 || true)"
else
  current_theme=""
  current_plugins=""
fi

if [ "$current_theme" = "ZSH_THEME=$DESIRED_ZSH_THEME" ]; then
  echo "  [skip]    ZSH_THEME=$DESIRED_ZSH_THEME (already set in $ZSHRC)"
else
  echo "  [set]     ZSH_THEME=$DESIRED_ZSH_THEME (currently: ${current_theme:-<unset>})"
  theme_needs_update=true
fi

if [ "$current_plugins" = "plugins=$DESIRED_PLUGINS" ]; then
  echo "  [skip]    plugins=$DESIRED_PLUGINS (already set in $ZSHRC)"
else
  echo "  [set]     plugins=$DESIRED_PLUGINS (currently: ${current_plugins:-<unset>})"
  plugins_needs_update=true
fi

echo ""

if [ ${#to_install_formulae[@]} -eq 0 ] && [ ${#to_install_casks[@]} -eq 0 ] \
  && [ "$omz_needs_install" = false ] && [ "$theme_needs_update" = false ] && [ "$plugins_needs_update" = false ]; then
  echo "everything is already installed: nothing to do."
  exit 0
fi

if [ "$APPLY" != true ]; then
  echo "dry-run: re-run with --apply to install the missing tools above."
  exit 0
fi

if [ ${#to_install_formulae[@]} -gt 0 ]; then
  echo "installing formulae: ${to_install_formulae[*]}"
  brew install "${to_install_formulae[@]}"
fi

if [ ${#to_install_casks[@]} -gt 0 ]; then
  echo "installing casks: ${to_install_casks[*]}"
  brew install --cask "${to_install_casks[@]}"
fi

if [ "$omz_needs_install" = true ]; then
  echo "installing oh-my-zsh..."
  # Non-interactive: keep the existing .zshrc (just append/edit into it below),
  # don't launch zsh afterwards, and don't change the login shell.
  KEEP_ZSHRC=yes RUNZSH=no CHSH=no sh -c "$(curl -fsSL "$OMZ_INSTALL_URL")" "" --unattended
fi

if [ "$theme_needs_update" = true ] || [ "$plugins_needs_update" = true ]; then
  if [ ! -f "$ZSHRC" ]; then
    echo "note: $ZSHRC did not exist; creating it"
    touch "$ZSHRC"
  fi
  if [ "$theme_needs_update" = true ]; then
    if grep -qE '^ZSH_THEME=' "$ZSHRC"; then
      sed -i '' -E "s|^ZSH_THEME=.*|ZSH_THEME=$DESIRED_ZSH_THEME|" "$ZSHRC"
    else
      printf '\nZSH_THEME=%s\n' "$DESIRED_ZSH_THEME" >>"$ZSHRC"
    fi
    echo "set ZSH_THEME=$DESIRED_ZSH_THEME in $ZSHRC"
  fi
  if [ "$plugins_needs_update" = true ]; then
    if grep -qE '^plugins=' "$ZSHRC"; then
      sed -i '' -E "s|^plugins=.*|plugins=$DESIRED_PLUGINS|" "$ZSHRC"
    else
      printf '\nplugins=%s\n' "$DESIRED_PLUGINS" >>"$ZSHRC"
    fi
    echo "set plugins=$DESIRED_PLUGINS in $ZSHRC"
  fi
fi

echo ""
echo "done."
