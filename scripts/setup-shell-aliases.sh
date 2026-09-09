#!/usr/bin/env bash
# Install (or remove) the sre-toolkit shell aliases in your shell rc file.
#
# The aliases themselves live in shell/aliases.sh next to this repo. The rc
# file only ever gets a small, marker-delimited block that sources that file,
# so pulling this repo updates your aliases and uninstalling is exact.
#
# Platform/shell detection picks the rc file that every interactive shell
# actually reads:
#
#   any + bash -> ~/.bashrc
#   any + zsh  -> ${ZDOTDIR:-$HOME}/.zshrc
#
# Bash only reads ~/.bashrc in non-login interactive shells, so for bash we
# also make sure the login file (~/.bash_profile, or whichever of
# ~/.bash_login / ~/.profile bash actually reads) sources ~/.bashrc. That is
# what makes the aliases show up by default in every bash session - login or
# not, terminal tab or `bash` subshell - rather than only some of them.
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

BOOTSTRAP_BEGIN_MARKER="# >>> sre-toolkit bashrc bootstrap >>>"
BOOTSTRAP_END_MARKER="# <<< sre-toolkit bashrc bootstrap <<<"

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

RC_FILE_EXPLICIT=false
if [ -n "$RC_FILE" ]; then
  RC_FILE_EXPLICIT=true
else
  case "$SHELL_NAME" in
    zsh)  RC_FILE="${ZDOTDIR:-$HOME}/.zshrc" ;;
    bash) RC_FILE="$HOME/.bashrc" ;;
  esac
fi

# Bash login shells (a macOS terminal tab, an ssh session) read the login file
# and skip ~/.bashrc entirely. Find the login file bash would actually use -
# the first of these that exists - so we can point it at ~/.bashrc.
BOOTSTRAP_FILE=""
if [ "$SHELL_NAME" = bash ] && [ "$RC_FILE_EXPLICIT" != true ]; then
  for candidate in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
    if [ -f "$candidate" ]; then
      BOOTSTRAP_FILE="$candidate"
      break
    fi
  done
  if [ -z "$BOOTSTRAP_FILE" ]; then
    # None exist yet. Create the one that is conventional for the platform.
    case "$PLATFORM" in
      macos) BOOTSTRAP_FILE="$HOME/.bash_profile" ;;
      *)     BOOTSTRAP_FILE="$HOME/.profile" ;;
    esac
  fi
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

# The rc block sources the two files by absolute path. If the repo has been
# moved or removed since install, say so in interactive shells instead of
# silently dropping the aliases - a silent no-op is very hard to notice.
BLOCK="$BEGIN_MARKER
# Managed by sre-toolkit/scripts/setup-shell-aliases.sh - edit shell/aliases.sh
# or shell/completions.sh to change what's loaded, or re-run the script to
# repoint this block.
for _sre_toolkit_file in \"$ALIASES_FILE\" \"$COMPLETIONS_FILE\"; do
  if [ -r \"\$_sre_toolkit_file\" ]; then
    . \"\$_sre_toolkit_file\"
  else
    case \$- in
      *i*) echo \"sre-toolkit: cannot read \$_sre_toolkit_file - re-run scripts/setup-shell-aliases.sh --apply to repoint this block\" >&2 ;;
    esac
  fi
done
unset _sre_toolkit_file
$END_MARKER"

# Bash reads ~/.bashrc only in non-login interactive shells. This one-liner in
# the login file is what makes login shells load it too, so both kinds of bash
# session get the aliases.
BOOTSTRAP_BLOCK="$BOOTSTRAP_BEGIN_MARKER
# Managed by sre-toolkit/scripts/setup-shell-aliases.sh - bash login shells
# skip ~/.bashrc, so source it here to get the same aliases in every shell.
[ -r \"\$HOME/.bashrc\" ] && . \"\$HOME/.bashrc\"
$BOOTSTRAP_END_MARKER"

# --- block helpers -----------------------------------------------------------

extract_block() {
  # extract_block <file> <begin> <end> - print the marker block, inclusive.
  awk -v b="$2" -v e="$3" '
    $0 == b { inblk = 1 }
    inblk   { print }
    $0 == e { inblk = 0 }
  ' "$1"
}

strip_block() {
  # strip_block <begin> <end> - remove the marker block (inclusive) from stdin,
  # along with the single blank separator line we insert before it, so an
  # uninstall restores the file byte for byte. Blank lines the user already had
  # are preserved: only one is consumed, and only when it directly precedes the
  # begin marker.
  awk -v b="$1" -v e="$2" '
    function flush() { for (i = 1; i <= nblank; i++) print ""; nblank = 0 }
    $0 == b  { if (nblank > 0) nblank--; flush(); inblk = 1; next }
    $0 == e  { inblk = 0; next }
    inblk    { next }
    $0 == "" { nblank++; next }
             { flush(); print }
    END      { flush() }
  '
}

backup_file() {
  local backup
  backup="$1.sre-toolkit.bak.$(date +%Y%m%d%H%M%S)"
  cp -p -- "$1" "$backup"
  echo "backed up $1 -> $backup"
}

write_block() {
  # write_block <file> <begin> <end> <block> - append the block, replacing any
  # existing copy of it. Creates the file if it does not exist.
  local file="$1" begin="$2" end="$3" block="$4" tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/sre-toolkit-rc.XXXXXX")"
  if [ -f "$file" ]; then
    backup_file "$file"
    strip_block "$begin" "$end" <"$file" >"$tmp"
    # Keep exactly one blank line between the previous content and our block.
    if [ -s "$tmp" ]; then
      printf '\n' >>"$tmp"
    fi
    printf '%s\n' "$block" >>"$tmp"
    cat -- "$tmp" >"$file"   # preserves the file's existing mode/owner
  else
    mkdir -p -- "$(dirname -- "$file")"
    echo "note: $file did not exist; creating it"
    printf '%s\n' "$block" >"$tmp"
    install -m 600 -- "$tmp" "$file" 2>/dev/null || { cat -- "$tmp" >"$file"; chmod 600 -- "$file"; }
  fi
  rm -f -- "$tmp"
}

remove_block() {
  # remove_block <file> <begin> <end>
  local file="$1" tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/sre-toolkit-rc.XXXXXX")"
  backup_file "$file"
  strip_block "$2" "$3" <"$file" >"$tmp"
  cat -- "$tmp" >"$file"
  rm -f -- "$tmp"
}

# --- current state -----------------------------------------------------------

installed=false
up_to_date=false
if [ -f "$RC_FILE" ] && grep -qxF "$BEGIN_MARKER" "$RC_FILE"; then
  installed=true
  if [ "$(extract_block "$RC_FILE" "$BEGIN_MARKER" "$END_MARKER")" = "$BLOCK" ]; then
    up_to_date=true
  fi
fi

# The bootstrap is only needed when the login file does not already pull in
# ~/.bashrc by itself - most Linux distributions ship a ~/.profile that does.
# Look at the file with our own block stripped out, so the check stays honest
# on a re-run.
bootstrap_installed=false
bootstrap_needed=false
bootstrap_up_to_date=false
if [ -n "$BOOTSTRAP_FILE" ] && [ "$RC_FILE" = "$HOME/.bashrc" ]; then
  if [ -f "$BOOTSTRAP_FILE" ] && grep -qxF "$BOOTSTRAP_BEGIN_MARKER" "$BOOTSTRAP_FILE"; then
    bootstrap_installed=true
    if [ "$(extract_block "$BOOTSTRAP_FILE" "$BOOTSTRAP_BEGIN_MARKER" "$BOOTSTRAP_END_MARKER")" = "$BOOTSTRAP_BLOCK" ]; then
      bootstrap_up_to_date=true
    fi
  fi
  if [ ! -f "$BOOTSTRAP_FILE" ]; then
    bootstrap_needed=true
  elif ! strip_block "$BOOTSTRAP_BEGIN_MARKER" "$BOOTSTRAP_END_MARKER" <"$BOOTSTRAP_FILE" \
       | grep -q '\.bashrc'; then
    bootstrap_needed=true
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
if [ -n "$BOOTSTRAP_FILE" ] && [ "$RC_FILE" = "$HOME/.bashrc" ]; then
  echo "login file:   $BOOTSTRAP_FILE$([ -f "$BOOTSTRAP_FILE" ] || echo '  (does not exist yet)')"
  if [ "$bootstrap_installed" = true ]; then
    echo "              sources ~/.bashrc via the sre-toolkit bootstrap$([ "$bootstrap_up_to_date" = true ] || echo ' (outdated)')"
  elif [ "$bootstrap_needed" = true ]; then
    echo "              does not source ~/.bashrc - login shells would miss the aliases"
  else
    echo "              already sources ~/.bashrc on its own - no bootstrap needed"
  fi
fi
echo ""
echo "aliases defined in $ALIASES_FILE:"
grep -E '^[[:space:]]*alias[[:space:]]' "$ALIASES_FILE" | sed 's/^/  /' || echo "  (none)"
echo ""
echo "completions wired in $COMPLETIONS_FILE (loaded only if the tool is installed):"
grep -oE '^\s*command -v [a-zA-Z0-9_-]+' "$COMPLETIONS_FILE" | awk '{print "  " $3}' || echo "  (none)"
echo ""

# --- uninstall ---------------------------------------------------------------

if [ "$UNINSTALL" = true ]; then
  if [ "$installed" != true ] && [ "$bootstrap_installed" != true ]; then
    echo "nothing to remove: no sre-toolkit block in $RC_FILE"
    exit 0
  fi
  if [ "$APPLY" != true ]; then
    [ "$installed" = true ] && echo "dry-run: would remove the sre-toolkit block from $RC_FILE"
    [ "$bootstrap_installed" = true ] && echo "dry-run: would remove the sre-toolkit bootstrap from $BOOTSTRAP_FILE"
    echo "re-run with --apply to remove it."
    exit 0
  fi
  if [ "$installed" = true ]; then
    remove_block "$RC_FILE" "$BEGIN_MARKER" "$END_MARKER"
    echo "removed the sre-toolkit block from $RC_FILE"
  fi
  if [ "$bootstrap_installed" = true ]; then
    remove_block "$BOOTSTRAP_FILE" "$BOOTSTRAP_BEGIN_MARKER" "$BOOTSTRAP_END_MARKER"
    echo "removed the sre-toolkit bootstrap from $BOOTSTRAP_FILE"
  fi
  echo "open a new shell (or run: unalias glg glga glgp) to drop the aliases."
  exit 0
fi

# --- install -----------------------------------------------------------------

want_bootstrap=false
if [ "$bootstrap_needed" = true ] || { [ "$bootstrap_installed" = true ] && [ "$bootstrap_up_to_date" != true ]; }; then
  want_bootstrap=true
fi

if [ "$up_to_date" = true ] && [ "$want_bootstrap" != true ]; then
  echo "already installed and up to date: nothing to do."
  echo "aliases live in $ALIASES_FILE - edit that file, no need to re-run this."
  exit 0
fi

if [ "$APPLY" != true ]; then
  if [ "$up_to_date" != true ]; then
    if [ "$installed" = true ]; then
      echo "dry-run: would replace the existing sre-toolkit block in $RC_FILE with:"
    else
      echo "dry-run: would append to $RC_FILE:"
    fi
    echo ""
    printf '%s\n' "$BLOCK" | sed 's/^/  /'
    echo ""
  fi
  if [ "$want_bootstrap" = true ]; then
    echo "dry-run: would append to $BOOTSTRAP_FILE, so login shells read ~/.bashrc too:"
    echo ""
    printf '%s\n' "$BOOTSTRAP_BLOCK" | sed 's/^/  /'
    echo ""
  fi
  echo "re-run with --apply to write it."
  exit 0
fi

if [ "$up_to_date" != true ]; then
  write_block "$RC_FILE" "$BEGIN_MARKER" "$END_MARKER" "$BLOCK"
  echo "installed the sre-toolkit block in $RC_FILE"
fi

if [ "$want_bootstrap" = true ]; then
  write_block "$BOOTSTRAP_FILE" "$BOOTSTRAP_BEGIN_MARKER" "$BOOTSTRAP_END_MARKER" "$BOOTSTRAP_BLOCK"
  echo "pointed $BOOTSTRAP_FILE at ~/.bashrc, so login shells load the aliases too"
fi

echo ""
echo "activate it in this shell with:"
echo "  source \"$RC_FILE\""
echo "or just open a new terminal."
