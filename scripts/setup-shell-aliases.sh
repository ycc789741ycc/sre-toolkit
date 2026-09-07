#!/usr/bin/env bash
# Install (or remove) the sre-toolkit shell aliases in your shell rc file.
#
# The aliases themselves live in shell/aliases.sh next to this repo. The rc
# file only ever gets a small, marker-delimited block that sources that file,
# so pulling this repo updates your aliases and uninstalling is exact.
#
# Platform/shell detection picks the rc file that is actually read by an
# interactive login shell:
#
#   macOS + bash  -> ~/.bash_profile   (login shells skip ~/.bashrc)
#   Linux + bash  -> ~/.bashrc
#   any   + zsh   -> ${ZDOTDIR:-$HOME}/.zshrc
#
# Default is dry-run; pass --apply to write. The rc file is backed up before
# any modification.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ALIASES_FILE="$REPO_DIR/shell/aliases.sh"
COMPLETIONS_FILE="$REPO_DIR/shell/completions.sh"

BEGIN_MARKER="# >>> sre-toolkit aliases >>>"
END_MARKER="# <<< sre-toolkit aliases <<<"

APPLY=false
UNINSTALL=false
RC_FILE=""
SHELL_NAME=""

usage() {
  cat <<'USAGE'
Usage: setup-shell-aliases.sh [--apply] [--uninstall] [--shell bash|zsh] [--rc-file <path>]

  --apply          Write the change. Default is dry-run: report what would
                   happen and exit without touching anything.
  --uninstall      Remove the sre-toolkit block instead of installing it.
  --shell NAME     Force bash or zsh instead of auto-detecting from $SHELL.
  --rc-file PATH   Write to this rc file instead of the auto-detected one.
  -h, --help       Show this help.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=true; shift ;;
    --uninstall) UNINSTALL=true; shift ;;
    --shell) SHELL_NAME="${2:-}"; shift 2 ;;
    --rc-file) RC_FILE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

# --- platform / shell detection ---------------------------------------------

case "$(uname -s)" in
  Darwin) PLATFORM=macos ;;
  Linux)  PLATFORM=linux ;;
  *)      PLATFORM="$(uname -s)" ;;
esac

if [ -z "$SHELL_NAME" ]; then
  SHELL_NAME="$(basename -- "${SHELL:-}")"
fi

case "$SHELL_NAME" in
  bash|zsh) ;;
  "")
    echo "error: could not detect your shell (\$SHELL is empty)" >&2
    echo "hint: pass --shell bash|zsh, or --rc-file <path>" >&2
    exit 1
    ;;
  *)
    echo "error: unsupported shell '$SHELL_NAME' (bash and zsh are supported)" >&2
    echo "hint: pass --rc-file <path> to install into it anyway" >&2
    exit 1
    ;;
esac

if [ -z "$RC_FILE" ]; then
  case "$SHELL_NAME:$PLATFORM" in
    zsh:*)        RC_FILE="${ZDOTDIR:-$HOME}/.zshrc" ;;
    bash:macos)   RC_FILE="$HOME/.bash_profile" ;;
    bash:linux)   RC_FILE="$HOME/.bashrc" ;;
    bash:*)       RC_FILE="$HOME/.bashrc" ;;
  esac
fi

if [ ! -f "$ALIASES_FILE" ]; then
  echo "error: aliases file not found: $ALIASES_FILE" >&2
  exit 1
fi

if [ ! -f "$COMPLETIONS_FILE" ]; then
  echo "error: completions file not found: $COMPLETIONS_FILE" >&2
  exit 1
fi

# --- current state -----------------------------------------------------------

BLOCK="$BEGIN_MARKER
# Managed by sre-toolkit/scripts/setup-shell-aliases.sh - edit shell/aliases.sh
# or shell/completions.sh to change what's loaded, or re-run the script to
# repoint this block.
[ -r \"$ALIASES_FILE\" ] && . \"$ALIASES_FILE\"
[ -r \"$COMPLETIONS_FILE\" ] && . \"$COMPLETIONS_FILE\"
$END_MARKER"

installed=false
up_to_date=false
if [ -f "$RC_FILE" ] && grep -qxF "$BEGIN_MARKER" "$RC_FILE"; then
  installed=true
  current_block="$(awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
    $0 == b { inblk = 1 }
    inblk   { print }
    $0 == e { inblk = 0 }
  ' "$RC_FILE")"
  if [ "$current_block" = "$BLOCK" ]; then
    up_to_date=true
  fi
fi

echo "platform:     $PLATFORM"
echo "shell:        $SHELL_NAME"
echo "rc file:      $RC_FILE$([ -f "$RC_FILE" ] || echo '  (does not exist yet)')"
echo "aliases file: $ALIASES_FILE"
echo "completions file: $COMPLETIONS_FILE"
if [ "$installed" = true ]; then
  echo "status:       block present$([ "$up_to_date" = true ] && echo ', up to date' || echo ', points elsewhere / outdated')"
else
  echo "status:       not installed"
fi
echo ""
echo "aliases defined in $ALIASES_FILE:"
grep -E '^[[:space:]]*alias[[:space:]]' "$ALIASES_FILE" | sed 's/^/  /' || echo "  (none)"
echo ""
echo "completions wired in $COMPLETIONS_FILE (loaded only if the tool is installed):"
grep -oE '^\s*command -v [a-zA-Z0-9_-]+' "$COMPLETIONS_FILE" | awk '{print "  " $3}' || echo "  (none)"
echo ""

# --- strip / write -----------------------------------------------------------

strip_block() {
  # Remove the marker block (inclusive) from stdin, along with the single blank
  # separator line we insert before it, so an uninstall restores the rc file
  # byte for byte. Blank lines the user already had are preserved: only one is
  # consumed, and only when it directly precedes the begin marker.
  awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" '
    function flush() { for (i = 1; i <= nblank; i++) print ""; nblank = 0 }
    $0 == b  { if (nblank > 0) nblank--; flush(); inblk = 1; next }
    $0 == e  { inblk = 0; next }
    inblk    { next }
    $0 == "" { nblank++; next }
             { flush(); print }
    END      { flush() }
  '
}

backup_rc() {
  local backup
  backup="$RC_FILE.sre-toolkit.bak.$(date +%Y%m%d%H%M%S)"
  cp -p -- "$RC_FILE" "$backup"
  echo "backed up $RC_FILE -> $backup"
}

if [ "$UNINSTALL" = true ]; then
  if [ "$installed" != true ]; then
    echo "nothing to remove: no sre-toolkit block in $RC_FILE"
    exit 0
  fi
  if [ "$APPLY" != true ]; then
    echo "dry-run: would remove the sre-toolkit block from $RC_FILE"
    echo "re-run with --apply to remove it."
    exit 0
  fi
  backup_rc
  tmp="$(mktemp "${TMPDIR:-/tmp}/sre-toolkit-rc.XXXXXX")"
  trap 'rm -f -- "$tmp"' EXIT
  strip_block <"$RC_FILE" >"$tmp"
  cat -- "$tmp" >"$RC_FILE"
  echo "removed the sre-toolkit block from $RC_FILE"
  echo "open a new shell (or run: unalias glg glga glgp) to drop the aliases."
  exit 0
fi

if [ "$up_to_date" = true ]; then
  echo "already installed and up to date: nothing to do."
  echo "aliases live in $ALIASES_FILE - edit that file, no need to re-run this."
  exit 0
fi

if [ "$APPLY" != true ]; then
  if [ "$installed" = true ]; then
    echo "dry-run: would replace the existing sre-toolkit block in $RC_FILE with:"
  else
    echo "dry-run: would append to $RC_FILE:"
  fi
  echo ""
  printf '%s\n' "$BLOCK" | sed 's/^/  /'
  echo ""
  echo "re-run with --apply to write it."
  exit 0
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/sre-toolkit-rc.XXXXXX")"
trap 'rm -f -- "$tmp"' EXIT

if [ -f "$RC_FILE" ]; then
  backup_rc
  strip_block <"$RC_FILE" >"$tmp"
  # Keep exactly one blank line between the previous content and our block.
  if [ -s "$tmp" ]; then
    printf '\n' >>"$tmp"
  fi
else
  mkdir -p -- "$(dirname -- "$RC_FILE")"
  : >"$tmp"
  echo "note: $RC_FILE did not exist; creating it"
fi

printf '%s\n' "$BLOCK" >>"$tmp"

if [ -f "$RC_FILE" ]; then
  cat -- "$tmp" >"$RC_FILE"   # preserves the rc file's existing mode/owner
else
  install -m 600 -- "$tmp" "$RC_FILE" 2>/dev/null || { cat -- "$tmp" >"$RC_FILE"; chmod 600 -- "$RC_FILE"; }
fi

echo "installed the sre-toolkit block in $RC_FILE"
echo ""
echo "activate it in this shell with:"
echo "  source \"$RC_FILE\""
echo "or just open a new terminal."
