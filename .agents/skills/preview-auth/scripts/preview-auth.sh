#!/usr/bin/env bash
#
# preview-auth — set up (or tear down) ONE Firebase Hosting preview host so real
# phone/Google sign-in works on it.
#
# LOCAL, human-invoked. It mutates PRODUCTION Firebase config (Firebase Auth
# authorized domains and the browser API key's HTTP referrers). Never run it in
# CI. Read the SKILL.md beside this script first.
#
# Requires: bash, curl, jq, gcloud (authenticated, with permission to update the
# API key and the Identity Toolkit config for the project).
#
# Usage (run from the repo root):
#   .agents/skills/preview-auth/scripts/preview-auth.sh list
#   .agents/skills/preview-auth/scripts/preview-auth.sh add    <host> [--apply]
#   .agents/skills/preview-auth/scripts/preview-auth.sh remove <host> [--apply]
#
# <host> is a bare host, e.g. wish-together-project--pr-12-abcde.web.app
# Without --apply the script only reads, prints the planned change, and writes a
# backup — it writes nothing. Add --apply to actually update Firebase.
#
# Every mutation preserves apiTargets and every existing referrer, adds/removes
# ONLY the exact `https://<host>/*` entry (never a wildcard), and sends the
# key's etag so a concurrent change fails closed.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-wish-together-project}"
TOKEN="${TOKEN:-}"
BACKUP_DIR="${PREVIEW_AUTH_BACKUP_DIR:-$HOME/.cache/wishtogether-preview-auth}"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
FIREBASE_OPTIONS="$REPO_ROOT/lib/firebase_options.dart"

API="https://apikeys.googleapis.com/v2"
ITK="https://identitytoolkit.googleapis.com/admin/v2"

die() { echo "error: $*" >&2; exit 1; }
note() { echo "• $*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

authorize() {
  [[ -n "$TOKEN" ]] || TOKEN="$(gcloud auth print-access-token)" \
    || die "gcloud auth print-access-token failed; run 'gcloud auth login'"
}

api_get()   { curl -fsS -H "Authorization: Bearer $TOKEN" "$API/$1"; }
api_patch() { curl -fsS -X PATCH -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: application/json" -d "$2" "$API/$1"; }
itk_get()   { curl -fsS -H "Authorization: Bearer $TOKEN" "$ITK/$1"; }
itk_patch() { curl -fsS -X PATCH -H "Authorization: Bearer $TOKEN" \
                -H "Content-Type: application/json" -d "$2" "$ITK/$1"; }

# The browser (web) API key from the generated Firebase web config.
web_api_key() {
  [[ -f "$FIREBASE_OPTIONS" ]] || die "not found: $FIREBASE_OPTIONS (run from the repo root)"
  awk '/FirebaseOptions web/{f=1} f && /apiKey:/{print; exit}' "$FIREBASE_OPTIONS" \
    | sed -E "s/.*'([^']+)'.*/\1/"
}

# Locate the API Keys API resource name of the browser key: the key whose
# keyString matches the web apiKey from firebase_options.dart.
find_key() {
  local wk keys key_name key_string
  wk="$(web_api_key)"
  [[ -n "$wk" ]] || die "could not read the web apiKey from $FIREBASE_OPTIONS"
  keys="$(api_get "projects/$PROJECT_ID/locations/global/keys?pageSize=200")"
  while IFS= read -r key_name; do
    [[ -n "$key_name" ]] || continue
    key_string="$(api_get "$key_name" | jq -r '.keyString // empty')"
    if [[ "$key_string" == "$wk" ]]; then
      echo "$key_name"
      return 0
    fi
  done < <(echo "$keys" | jq -r '.keys[]?.name')
  return 1
}

print_google_step() {
  cat <<EOF

  Google sign-in needs one more list, which has no public API:
    Google Cloud Console -> APIs & Services -> Credentials
      -> the project's "Web client (auto created by Google Service)"
      -> Authorized JavaScript origins -> Add URI ->  https://${1:-<host>}

EOF
}

cmd_list() {
  authorize
  echo "== Firebase Auth authorized domains (project $PROJECT_ID) =="
  itk_get "projects/$PROJECT_ID/config" | jq -r '.authorizedDomains[]?'
  echo
  echo "== Browser API key HTTP referrers =="
  local key
  key="$(find_key)" || die "no API key matched a web apiKey in firebase_options.dart"
  api_get "$key" \
    | jq -r '"key: \(.keyString)\napiTargets: \(.restrictions.apiTargets // [] | join(", "))\nreferrers:\n" + ([.restrictions.browserKeyRestrictions.allowedReferrers[]?] | join("\n"))'
}

mutate() {
  local mode="$1" host="$2" flag="${3:-}"
  [[ -n "$host" ]] || die "usage: preview-auth.sh $mode <host> [--apply]"
  [[ "$host" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || die "invalid host: $host"
  authorize

  local key key_json etag entry refs_json targets_json body backup stamp
  key="$(find_key)" || die "could not locate the browser API key (no keyString match in firebase_options.dart)"
  key_json="$(api_get "$key")"
  etag="$(jq -r '.etag' <<<"$key_json")"
  entry="https://$host/*"

  case "$mode" in
    add)
      refs_json="$(jq -c --arg e "$entry" \
        '(.restrictions.browserKeyRestrictions.allowedReferrers // []) + [$e] | unique' <<<"$key_json")" ;;
    remove)
      refs_json="$(jq -c --arg e "$entry" \
        '(.restrictions.browserKeyRestrictions.allowedReferrers // []) | map(select(. != $e))' <<<"$key_json")" ;;
    *)
      die "unknown mode: $mode" ;;
  esac
  targets_json="$(jq -c '.restrictions.apiTargets // []' <<<"$key_json")"

  mkdir -p "$BACKUP_DIR"
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup="$BACKUP_DIR/key-${stamp}.json"
  printf '%s\n' "$key_json" > "$backup"
  note "backup of current key restrictions: $backup"

  body="$(jq -cn --arg etag "$etag" --argjson refs "$refs_json" --argjson targets "$targets_json" \
    '{etag: $etag, restrictions: {browserKeyRestrictions: {allowedReferrers: $refs}, apiTargets: $targets}}')"

  echo "Planned PATCH $API/$key?updateMask=restrictions.browserKeyRestrictions.allowedReferrers"
  echo "$body" | jq .

  if [[ "$flag" != "--apply" ]]; then
    note "dry run: nothing written. Re-run with --apply to write."
    [[ "$mode" == add ]] && print_google_step "$host"
    return 0
  fi

  api_patch "$key?updateMask=restrictions.browserKeyRestrictions.allowedReferrers" "$body" >/dev/null
  note "browser API key referrers updated"

  # Auth authorized domain: only patch when the list actually changes.
  local cfg new_domains
  cfg="$(itk_get "projects/$PROJECT_ID/config")"
  case "$mode" in
    add)    new_domains="$(jq -c --arg h "$host" '.authorizedDomains + [$h] | unique' <<<"$cfg")" ;;
    remove) new_domains="$(jq -c --arg h "$host" '.authorizedDomains | map(select(. != $h))' <<<"$cfg")" ;;
  esac
  if [[ "$(jq -c '.authorizedDomains' <<<"$cfg")" != "$new_domains" ]]; then
    itk_patch "projects/$PROJECT_ID/config?updateMask=authorizedDomains" \
      "$(jq -cn --argjson d "$new_domains" '{authorizedDomains: $d}')" >/dev/null
    note "Auth authorized domains updated for $host"
  else
    note "Auth authorized domain already $([[ "$mode" == add ]] && echo present || echo absent): $host"
  fi

  [[ "$mode" == add ]] && print_google_step "$host"
  return 0
}

main() {
  local cmd="${1:-}"; shift || true
  local host="${1:-}" flag="${2:-}"
  case "$cmd" in
    list) ;;
    add|remove)
      [[ -n "$host" ]] || die "usage: preview-auth.sh $cmd <host> [--apply]"
      [[ "$host" =~ ^[a-z0-9][a-z0-9.-]*$ ]] || die "invalid host: $host"
      ;;
    *) die "usage: preview-auth.sh {list|add <host>|remove <host>} [--apply]" ;;
  esac
  need curl; need jq; need gcloud
  case "$cmd" in
    list)   cmd_list ;;
    add)    mutate add "$host" "$flag" ;;
    remove) mutate remove "$host" "$flag" ;;
  esac
}

main "$@"
