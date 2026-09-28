#!/usr/bin/env bash
# Thin CLI over the OurPulse REST API. Needs OURPULSE_API_KEY; OURPULSE_URL defaults to production.
set -euo pipefail
BASE="${OURPULSE_URL:-https://pulse.1153nikidimitrov.workers.dev}"

# `check` diagnoses the key and prints what to do. Exit 0 ok, 3 missing, 4 rejected.
if [ "${1:-}" = check ]; then
  if [ -z "${OURPULSE_API_KEY:-}" ]; then
    cat >&2 <<EOF
OURPULSE_API_KEY is not set.
  1. Create a key at $BASE/me/keys (the page has a "Copy export line" button).
  2. Put it in your shell profile, e.g. ~/.zshrc:   export OURPULSE_API_KEY=pk_...
     or in Claude Code settings (~/.claude/settings.json):  { "env": { "OURPULSE_API_KEY": "pk_..." } }
  3. Restart the session so the variable is picked up.
EOF
    exit 3
  fi
  code=$(curl -sS -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $OURPULSE_API_KEY" "$BASE/api/surveys" || echo 000)
  case "$code" in
    200) echo "ok: key accepted by $BASE"; exit 0 ;;
    401|403) echo "OURPULSE_API_KEY is set but $BASE rejects it (HTTP $code). It may be revoked; create a new one at $BASE/me/keys." >&2; exit 4 ;;
    *) echo "cannot reach $BASE (HTTP $code)." >&2; exit 5 ;;
  esac
fi

: "${OURPULSE_API_KEY:?not set. Run: ourpulse.sh check}"

api() { curl -sS -H "Authorization: Bearer $OURPULSE_API_KEY" -H "Content-Type: application/json" "$@"; }

case "${1:-}" in
  create)   # create <json-file or ->   -> pulse JSON (id, url, qr_svg_url, ...)
    api -X POST "$BASE/api/surveys" --data-binary "@${2:--}" ;;
  get)      # get <id>
    api "$BASE/api/surveys/$2" ;;
  list)
    api "$BASE/api/surveys" ;;
  results)  # results <id>
    api "$BASE/api/surveys/$2/results" ;;
  csv)      # csv <id>
    api "$BASE/api/surveys/$2/export.csv" ;;
  pause|resume|close|reset)   # <action> <id>
    api -X POST "$BASE/api/surveys/$2/$1" ;;
  reopen)   # reopen <id> [days]
    api -X POST "$BASE/api/surveys/$2/reopen" -d "{\"days\": ${3:-7}}" ;;
  delete)   # delete <id>
    api -X DELETE "$BASE/api/surveys/$2" -o /dev/null -w "%{http_code}\n" ;;
  wait)     # wait <id> [interval-seconds]  -> blocks until closed, prints results
    id="$2"; every="${3:-60}"
    while :; do
      state=$(api "$BASE/api/surveys/$id" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("state","?"), d.get("response_count",0), d.get("expected") or "")')
      set -- $state
      if [ "$1" = closed ]; then api "$BASE/api/surveys/$id/results"; exit 0; fi
      echo "state=$1 answered=$2${3:+ of $3}" >&2
      sleep "$every"
    done ;;
  *)
    echo "usage: ourpulse.sh check | create <file|-> | get <id> | list | results <id> | csv <id> | wait <id> [secs]" >&2
    echo "       ourpulse.sh pause|resume|close|reset <id> | reopen <id> [days] | delete <id>" >&2; exit 2 ;;
esac
