#!/usr/bin/env bash
# Thin CLI over the OurPulse REST API.
# Key: OURPULSE_API_KEY if set, else the file written by `ourpulse.sh login`.
# OURPULSE_URL defaults to production.
set -euo pipefail
BASE="${OURPULSE_URL:-https://ourpulse.click}"
HOST="$(printf %s "$BASE" | sed -E 's#^[a-z]+://##; s#[/:].*$##')"
KEY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ourpulse"
KEY_FILE="$KEY_DIR/$HOST.key"

KEY="${OURPULSE_API_KEY:-}"
[ -z "$KEY" ] && [ -r "$KEY_FILE" ] && KEY="$(tr -d '[:space:]' < "$KEY_FILE")"

open_url() { command -v open >/dev/null && open "$1" 2>/dev/null || command -v xdg-open >/dev/null && xdg-open "$1" 2>/dev/null || true; }

# `login`: device-code flow. Opens the browser, waits for approval, saves the key. Never prints it.
if [ "${1:-}" = login ]; then
  label="Claude Code on $(hostname -s 2>/dev/null || hostname)"
  start=$(curl -sS -X POST -H "Content-Type: application/json" "$BASE/cli/device" -d "{\"label\": \"$label\"}") \
    || { echo "cannot reach $BASE" >&2; exit 5; }
  eval "$(printf %s "$start" | python3 -c 'import sys,json,shlex; d=json.load(sys.stdin); print("dc=%s uc=%s vurl=%s every=%s" % tuple(shlex.quote(str(d[k])) for k in ("device_code","user_code","verify_url","interval")))')"
  echo "Open this link and press Approve (code $uc):" >&2
  echo "  $vurl" >&2
  open_url "$vurl"
  deadline=$(( $(date +%s) + 600 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    sleep "$every"
    resp=$(curl -sS -w '\n%{http_code}' -X POST -H "Content-Type: application/json" "$BASE/cli/device/token" -d "{\"device_code\": \"$dc\"}")
    code="${resp##*$'\n'}"; body="${resp%$'\n'*}"
    case "$code" in
      428) continue ;;
      200)
        mkdir -p "$KEY_DIR"; chmod 700 "$KEY_DIR"
        printf %s "$body" | python3 -c 'import sys,json; d=json.load(sys.stdin); open(sys.argv[1],"w").write(d["key"]); print(d.get("email",""))' "$KEY_FILE" > "$KEY_DIR/.email"
        chmod 600 "$KEY_FILE"
        echo "connected to $BASE as $(cat "$KEY_DIR/.email"), key saved to $KEY_FILE" >&2; rm -f "$KEY_DIR/.email"; exit 0 ;;
      403) echo "denied in the browser; nothing saved." >&2; exit 4 ;;
      410) echo "the request expired; run login again." >&2; exit 4 ;;
      *)   echo "unexpected HTTP $code from $BASE" >&2; exit 5 ;;
    esac
  done
  echo "timed out waiting for approval; run login again." >&2; exit 4
fi

# `logout`: forget the local key. Revoke it on $BASE/me/keys if it should stop working everywhere.
if [ "${1:-}" = logout ]; then rm -f "$KEY_FILE"; echo "removed $KEY_FILE" >&2; exit 0; fi

# `check`: exit 0 when a key is present and accepted, 3 when missing, 4 when rejected, 5 when unreachable.
if [ "${1:-}" = check ]; then
  if [ -z "$KEY" ]; then echo "not logged in to $BASE. Run: ourpulse.sh login" >&2; exit 3; fi
  code=$(curl -sS -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $KEY" "$BASE/api/surveys" || echo 000)
  case "$code" in
    200) echo "ok: logged in to $BASE"; exit 0 ;;
    401|403) echo "the saved key was rejected by $BASE (HTTP $code), probably revoked. Run: ourpulse.sh login" >&2; exit 4 ;;
    *) echo "cannot reach $BASE (HTTP $code)." >&2; exit 5 ;;
  esac
fi

[ -n "$KEY" ] || { echo "not logged in. Run: ourpulse.sh login" >&2; exit 3; }

api() { curl -sS -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" "$@"; }

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
  schedule) # schedule <id> <closes_at-ms|-> [opens_at-ms]   -> set exact open/close instants
    parts=""; [ "${3:--}" != - ] && parts="\"closes_at\": $3"
    [ -n "${4:-}" ] && parts="${parts:+$parts, }\"opens_at\": $4"
    api -X PATCH "$BASE/api/surveys/$2" -d "{$parts}" ;;
  delete)   # delete <id>
    api -X DELETE "$BASE/api/surveys/$2" -o /dev/null -w "%{http_code}\n" ;;
  invite)   # invite <id>   -> prints invite_url and opens it in the default browser (TV / projector page)
    url=$(api "$BASE/api/surveys/$2" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("invite_url",""))')
    [ -n "$url" ] || { echo "no such pulse" >&2; exit 1; }
    echo "$url"
    if command -v open >/dev/null 2>&1; then open "$url"; elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1; fi ;;
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
    echo "usage: ourpulse.sh login | logout | check | create <file|-> | get <id> | list | results <id> | csv <id> | invite <id> | wait <id> [secs]" >&2
    echo "       ourpulse.sh pause|resume|close|reset <id> | reopen <id> [days] | schedule <id> <closes-ms|-> [opens-ms] | delete <id>" >&2; exit 2 ;;
esac
