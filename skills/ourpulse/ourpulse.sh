#!/usr/bin/env bash
# Thin CLI over the OurPulse REST API.
# Key, first match wins: OURPULSE_API_KEY, the key saved for this folder (`login --local`), the global key (`login`).
# All saved keys live under ~/.config/ourpulse/, never inside the project folder.
# OURPULSE_URL defaults to production.
set -euo pipefail
BASE="${OURPULSE_URL:-https://ourpulse.click}"
HOST="$(printf %s "$BASE" | sed -E 's#^[a-z]+://##; s#[/:].*$##')"
KEY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ourpulse"
KEY_FILE="$KEY_DIR/$HOST.key"

# "This folder" is the git root when inside a repository, otherwise the current directory.
FOLDER="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
FOLDER_ID="$(printf %s "$FOLDER" | { shasum -a 256 2>/dev/null || sha256sum; } | cut -c1-16)"
LOCAL_FILE="$KEY_DIR/$HOST.local/$FOLDER_ID.key"

KEY="${OURPULSE_API_KEY:-}"; SCOPE="OURPULSE_API_KEY"; USED_FILE=""
if [ -z "$KEY" ]; then
  if [ -r "$LOCAL_FILE" ]; then USED_FILE="$LOCAL_FILE"; SCOPE="this folder only: $FOLDER"
  elif [ -r "$KEY_FILE" ]; then USED_FILE="$KEY_FILE"; SCOPE="global"; fi
  [ -n "$USED_FILE" ] && KEY="$(tr -d '[:space:]' < "$USED_FILE")"
fi
EMAIL=""; [ -n "$USED_FILE" ] && [ -r "${USED_FILE%.key}.email" ] && EMAIL="$(tr -d '[:space:]' < "${USED_FILE%.key}.email")"

open_url() { command -v open >/dev/null && open "$1" 2>/dev/null || command -v xdg-open >/dev/null && xdg-open "$1" 2>/dev/null || true; }

# --local / --global, or by default the folder key when this folder has one, else the global key.
scope_arg() {
  case "${1:-}" in
    --local) echo local ;;
    --global) echo global ;;
    "") if [ -e "$LOCAL_FILE" ]; then echo local; else echo global; fi ;;
    *) echo "usage: ourpulse.sh login|logout [--local|--global]" >&2; exit 2 ;;
  esac
}

# `login [--local|--global]`: device-code flow. Opens the browser, waits for approval, saves the key. Never prints it.
if [ "${1:-}" = login ]; then
  target="$(scope_arg "${2:-}")"
  label="Claude Code on $(hostname -s 2>/dev/null || hostname)"
  if [ "$target" = local ]; then file="$LOCAL_FILE"; label="$label ($(basename "$FOLDER"))"; where="this folder only: $FOLDER"; else file="$KEY_FILE"; where="global"; fi
  req=$(python3 -c 'import sys,json; print(json.dumps({"label": sys.argv[1]}))' "$label")
  start=$(curl -sS -X POST -H "Content-Type: application/json" "$BASE/cli/device" -d "$req") \
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
        umask 077
        mkdir -p "$(dirname "$file")"; chmod 700 "$KEY_DIR" "$(dirname "$file")"
        printf %s "$body" | python3 -c 'import sys,json; d=json.load(sys.stdin); open(sys.argv[1],"w").write(d["key"]); print(d.get("email",""))' "$file" > "${file%.key}.email"
        [ "$target" = local ] && printf '%s\n' "$FOLDER" > "${file%.key}.path"
        echo "connected to $BASE as $(cat "${file%.key}.email") ($where), key saved to $file" >&2; exit 0 ;;
      403) echo "denied in the browser; nothing saved." >&2; exit 4 ;;
      410) echo "the request expired; run login again." >&2; exit 4 ;;
      *)   echo "unexpected HTTP $code from $BASE" >&2; exit 5 ;;
    esac
  done
  echo "timed out waiting for approval; run login again." >&2; exit 4
fi

# `logout [--local|--global]`: forget a saved key. Revoke it on $BASE/me/keys if it should stop working everywhere.
if [ "${1:-}" = logout ]; then
  if [ "$(scope_arg "${2:-}")" = local ]; then file="$LOCAL_FILE"; else file="$KEY_FILE"; fi
  rm -f "$file" "${file%.key}.email" "${file%.key}.path"; echo "removed $file" >&2; exit 0
fi

# `check`: exit 0 when a key is present and accepted, 3 when missing, 4 when rejected, 5 when unreachable.
# On success prints the account (when known) and which key is in use.
if [ "${1:-}" = check ]; then
  if [ -z "$KEY" ]; then echo "not logged in to $BASE. Run: ourpulse.sh login" >&2; exit 3; fi
  resp=$(curl -sS -w '\n%{http_code}' -H "Authorization: Bearer $KEY" "$BASE/api/me" || printf '\n000')
  code="${resp##*$'\n'}"
  if [ "$code" = 200 ]; then
    # Ask the server whose key this is, and remember it next to the key.
    who=$(printf %s "${resp%$'\n'*}" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("email",""))' 2>/dev/null || true)
    if [ -n "$who" ]; then EMAIL="$who"; [ -n "$USED_FILE" ] && printf '%s\n' "$who" > "${USED_FILE%.key}.email"; fi
  elif [ "$code" = 404 ]; then   # a server without /api/me
    code=$(curl -sS -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $KEY" "$BASE/api/surveys" || echo 000)
  fi
  case "$code" in
    200) echo "ok: logged in to $BASE${EMAIL:+ as $EMAIL} ($SCOPE)"; exit 0 ;;
    401|403) echo "the saved key ($SCOPE) was rejected by $BASE (HTTP $code), probably revoked. Run: ourpulse.sh login" >&2; exit 4 ;;
    *) echo "cannot reach $BASE (HTTP $code)." >&2; exit 5 ;;
  esac
fi

# `report-preview <html-file>`: wrap a report body in the page OurPulse serves it in and open it locally. Needs no key.
if [ "${1:-}" = report-preview ]; then
  [ -r "${2:-}" ] || { echo "usage: ourpulse.sh report-preview <html-file>" >&2; exit 2; }
  out="${TMPDIR:-/tmp}/ourpulse-report-preview-$$.html"
  python3 -c 'import sys; open(sys.argv[3],"w").write(open(sys.argv[1]).read().replace("<!--REPORT_BODY-->", open(sys.argv[2]).read()))' \
    "$(dirname "$0")/report-preview.html" "$2" "$out"
  echo "$out"
  open_url "$out"; exit 0
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
  report)   # report <id> <html-file>   -> push the report body; prints report_url. Replaces an earlier report, same link.
    [ -r "${3:-}" ] || { echo "usage: ourpulse.sh report <id> <html-file>" >&2; exit 2; }
    curl -sS -X PUT -H "Authorization: Bearer $KEY" -H "Content-Type: text/html; charset=utf-8" --data-binary "@$3" "$BASE/api/surveys/$2/report" ;;
  report-delete)   # report-delete <id>   -> remove the report; its link stops working
    api -X DELETE "$BASE/api/surveys/$2/report" -o /dev/null -w "%{http_code}\n" ;;
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
    echo "usage: ourpulse.sh login [--local|--global] | logout [--local|--global] | check | create <file|-> | get <id> | list | results <id> | csv <id> | invite <id> | wait <id> [secs]" >&2
    echo "       ourpulse.sh pause|resume|close|reset <id> | reopen <id> [days] | schedule <id> <closes-ms|-> [opens-ms] | delete <id>" >&2
    echo "       ourpulse.sh report-preview <html-file> | report <id> <html-file> | report-delete <id>" >&2; exit 2 ;;
esac
