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

if [ ${#to_install_formulae[@]} -eq 0 ] && [ ${#to_install_casks[@]} -eq 0 ]; then
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

echo ""
echo "done."
