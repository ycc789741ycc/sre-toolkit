#!/usr/bin/env bash
# Report on (default) or clean up stale VS Code Remote-SSH server installs
# and their zombie process trees on a remote host.
#
# VS Code Remote-SSH daemonizes its server per client version (commit hash)
# under ~/.vscode-server and leaves it running after disconnect so
# reconnects are fast. If a connection drops uncleanly (VPN/network blip,
# laptop sleep) instead of closing gracefully, the idle-shutdown timer
# never starts, and every client update adds another version's worth of
# leftover processes and ~700MB install. This script finds the newest
# version directory (by mtime) and treats every other version as stale:
# it reports them by default, and with --apply kills their process trees
# and deletes their install directories/binaries/logs.
set -euo pipefail

# Pick up HOST/SSH_USER from .env (next to this script, or in the repo root)
# so the script behaves the same whether run via `make` or directly.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for envfile in "$SCRIPT_DIR/.env" "$SCRIPT_DIR/../.env"; do
  if [ -f "$envfile" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$envfile"
    set +a
    break
  fi
done

HOST="${HOST:-}"
SSH_USER="${SSH_USER:-}"
APPLY=false
YES=false

usage() {
  cat <<'USAGE'
Usage: vscode-server-cleanup.sh [--host <host>] [--ssh-user <user>] [--apply] [--yes]

  --host HOST      Remote host to connect to. Defaults to $HOST from .env.
  --ssh-user USER  SSH user on the remote host. Defaults to $SSH_USER from .env.
  --apply          Actually kill stale processes and delete old version
                    installs. Default is a dry-run report only.
  --yes            Skip the confirmation prompt when --apply is set.
  -h, --help       Show this help.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --ssh-user) SSH_USER="$2"; shift 2 ;;
    --apply) APPLY=true; shift ;;
    --yes) YES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [ -z "$HOST" ]; then
  echo "error: no host given (pass --host, or set HOST in .env)" >&2
  usage
  exit 1
fi

if [ -n "$SSH_USER" ] && [[ "$HOST" != *"@"* ]]; then
  HOST="$SSH_USER@$HOST"
fi

if [ "$APPLY" = true ] && [ "$YES" != true ]; then
  read -r -p "This will kill stale VS Code server processes and delete old version installs on $HOST. Continue? [y/N] " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST" "APPLY=$APPLY bash -s" <<'REMOTE_EOF'
set -uo pipefail
cd "$HOME/.vscode-server" 2>/dev/null || { echo "No ~/.vscode-server directory found on $(hostname) - nothing to do."; exit 0; }

echo "== VS Code Server status on $(hostname) =="
echo "-- total size --"
du -sh . 2>/dev/null

newest=""
newest_time=0
for d in cli/servers/Stable-*/; do
  [ -d "$d" ] || continue
  case "$d" in *.staging/) continue ;; esac
  t=$(stat -c %Y "$d" 2>/dev/null || stat -f %m "$d" 2>/dev/null || echo 0)
  if [ "$t" -gt "$newest_time" ]; then
    newest_time=$t
    newest=$(basename "$d")
  fi
done
newest_hash="${newest#Stable-}"
echo "-- newest/active version: ${newest_hash:-<none found>} --"

echo
echo "-- version directories --"
stale_hashes=""
for d in cli/servers/Stable-*/; do
  [ -d "$d" ] || continue
  base=$(basename "$d")
  hash="${base%.staging}"
  hash="${hash#Stable-}"
  size=$(du -sh "$d" 2>/dev/null | cut -f1)
  if [ "$hash" = "$newest_hash" ]; then
    echo "  KEEP   $base ($size)"
  else
    nproc=$(pgrep -cf "$base" 2>/dev/null || echo 0)
    echo "  STALE  $base ($size) - running processes: $nproc"
    case " $stale_hashes " in
      *" $hash "*) ;;
      *) stale_hashes="$stale_hashes $hash" ;;
    esac
  fi
done

if [ -z "$stale_hashes" ]; then
  echo
  echo "Nothing to clean."
  exit 0
fi

if [ "${APPLY:-false}" != "true" ]; then
  echo
  echo "DRY RUN - no changes made. Re-run with --apply to remove the above and kill their processes."
  exit 0
fi

echo
echo "== Applying cleanup =="
for hash in $stale_hashes; do
  echo "-- stopping processes for $hash --"
  pkill -TERM -f "$hash" 2>/dev/null || true
done
sleep 3
for hash in $stale_hashes; do
  pkill -KILL -f "$hash" 2>/dev/null || true
done

for hash in $stale_hashes; do
  echo "-- removing files for $hash --"
  rm -rf "cli/servers/Stable-${hash}" "cli/servers/Stable-${hash}.staging"
  rm -f "code-${hash}" ".cli.${hash}.log"
done

echo
echo "-- new size --"
du -sh . 2>/dev/null
echo "Done."
REMOTE_EOF
