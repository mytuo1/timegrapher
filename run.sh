#!/usr/bin/env bash
# ============================================================================
# Timegrapher — local launcher (Linux / WSL / macOS)
# ----------------------------------------------------------------------------
# Serves the app on http://localhost:8000 using whichever HTTP server is
# available (python3 → python → busybox → node).  Microphone capture in
# browsers requires a *secure context*, which means either
#   - http://localhost     (treated as secure), or
#   - HTTPS with a valid certificate.
# This script binds to localhost, so getUserMedia will work in all browsers.
# ============================================================================
set -euo pipefail

PORT="${PORT:-8000}"
HOST="${HOST:-127.0.0.1}"
DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$DIR"

open_browser() {
  # Skip launching a browser when running headless / under systemd (NO_BROWSER=1).
  if [ -n "${NO_BROWSER:-}" ]; then return 0; fi
  local url="http://${HOST}:${PORT}/"
  if   command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 &
  elif command -v open      >/dev/null 2>&1; then open      "$url" >/dev/null 2>&1 &
  elif command -v wslview   >/dev/null 2>&1; then wslview   "$url" >/dev/null 2>&1 &
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
