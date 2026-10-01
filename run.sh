#!/usr/bin/env bash
# ============================================================================
# Timegrapher — portable launcher (Linux / WSL / macOS / EC2 / any VM)
# ----------------------------------------------------------------------------
# Serves this folder over HTTP using whichever server is available
# (python3 → python → node → busybox). No build step, no dependencies to install
# beyond one of those.
#
# Configuration (all optional, via environment):
#   PORT=8000        port to listen on
#   HOST=127.0.0.1   interface to bind (see "Remote / VM use" below)
#   NO_BROWSER=1     don't try to open a desktop browser (headless/VM/systemd)
#
# Microphone capture needs a *secure context* in the browser:
#   • http://localhost  or  http://127.0.0.1   → always allowed (default).
#   • http://<lan-ip>  (e.g. HOST=0.0.0.0 on a VM you browse from another
#     machine) → browsers BLOCK the mic. See "Remote / VM use" below.
#
# Remote / VM use (EC2, WSL, home server…):
#   The mic is captured by YOUR browser, so the server just needs to be reachable.
#   To keep a secure context when the server is on another host, use ONE of:
#     1. SSH port-forward (simplest, no TLS needed):
#            ssh -L 8000:127.0.0.1:8000 user@vm
#        then open http://localhost:8000 on your machine.
#     2. Put a TLS reverse proxy (Caddy/nginx) in front and browse to https://…
#   Binding to 0.0.0.0 without one of the above lets the page load but the mic
#   will be denied by the browser — that is a browser security rule, not a bug.
# ============================================================================
set -euo pipefail

PORT="${PORT:-8000}"
HOST="${HOST:-127.0.0.1}"
DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$DIR"

open_browser() {
  # Skip launching a browser when headless / under systemd (NO_BROWSER=1), or
  # when bound to a non-local address (a VM has no useful local browser).
  if [ -n "${NO_BROWSER:-}" ]; then return 0; fi
  case "$HOST" in 0.0.0.0|::|"") return 0 ;; esac
  local url="http://${HOST}:${PORT}/"
  if   command -v xdg-open     >/dev/null 2>&1; then xdg-open     "$url" >/dev/null 2>&1 &
  elif command -v open         >/dev/null 2>&1; then open         "$url" >/dev/null 2>&1 &
  elif command -v wslview      >/dev/null 2>&1; then wslview      "$url" >/dev/null 2>&1 &
  elif command -v explorer.exe >/dev/null 2>&1; then explorer.exe "$url" >/dev/null 2>&1 &
  else echo "Open this URL in your browser: $url"
  fi
}

banner() {
  cat <<EOF
─────────────────────────────────────────────
  ⌚  Timegrapher
  Serving:  ${DIR}
  URL:      http://${HOST}:${PORT}/
  Stop:     Ctrl-C
─────────────────────────────────────────────
EOF
  if [ "$HOST" != "127.0.0.1" ] && [ "$HOST" != "localhost" ]; then
    echo "NOTE: bound to ${HOST}. Mic needs a secure context — use an SSH tunnel" >&2
    echo "      (ssh -L ${PORT}:127.0.0.1:${PORT} …) or HTTPS. See header of run.sh." >&2
  fi
}

start_python3() { banner; (sleep 0.5 && open_browser) & exec python3 -m http.server "$PORT" --bind "$HOST"; }
start_python2() { banner; (sleep 0.5 && open_browser) & exec python  -m SimpleHTTPServer "$PORT"; }
start_node()    { banner; (sleep 0.5 && open_browser) & exec npx --yes http-server -a "$HOST" -p "$PORT" -c-1 .; }
start_busybox() { banner; (sleep 0.5 && open_browser) & exec busybox httpd -f -p "${HOST}:${PORT}" -h .; }

if   command -v python3 >/dev/null 2>&1; then start_python3
elif command -v python  >/dev/null 2>&1; then start_python2
elif command -v node    >/dev/null 2>&1; then start_node
elif command -v busybox >/dev/null 2>&1; then start_busybox
else
  echo "ERROR: need python3, python, node, or busybox in PATH." >&2
  exit 1
fi
