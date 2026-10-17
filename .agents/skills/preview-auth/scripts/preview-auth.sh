#!/usr/bin/env bash
#
# preview-auth — set up (or tear down) ONE Firebase Hosting preview host so real
# phone/Google sign-in works on it.
#
# LOCAL, human-invoked. It mutates PRODUCTION Firebase config (Firebase Auth
# authorized domains and the browser API key's HTTP referrers) for the project in
# .firebaserc. Never run it in CI. Read the SKILL.md beside this script first.
#
# Requires: bash, curl, jq, gcloud (authenticated, with permission to update the
# API key and the Identity Toolkit config for the project).
#
# Usage (run from anywhere inside the repo):
#   .agents/skills/preview-auth/scripts/preview-auth.sh list
#   .agents/skills/preview-auth/scripts/preview-auth.sh add    <host> [--apply]
#   .agents/skills/preview-auth/scripts/preview-auth.sh remove <host> [--apply]
#
# <host> must be a Firebase Hosting host of this project, e.g.
# wish-together-project--pr-12-abcde.web.app or wish-together-staging.web.app.
# Without --apply the script only reads and prints the planned change; no backup
# is written and Firebase is not modified. Add --apply to write (and back up).
#
# Every mutation preserves apiTargets and every existing referrer, changes only
# the exact `https://<host>/*` entry (never a wildcard, never reordered), sends
# the key's etag so a concurrent key change fails closed, and skips the API call
# when nothing would change.
set -euo pipefail
umask 077

PROJECT_ID="${PROJECT_ID:-}"
TOKEN="${TOKEN:-}"
BACKUP_DIR="${PREVIEW_AUTH_BACKUP_DIR:-$HOME/.cache/wishtogether-preview-auth}"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
FIREBASE_OPTIONS="${FIREBASE_OPTIONS:-$REPO_ROOT/lib/firebase_options.dart}"

API="https://apikeys.googleapis.com/v2"
ITK="https://identitytoolkit.googleapis.com/admin/v2"

# Populated by resolve_guard once PROJECT_ID is known.
HOST_REGEX=""
PROTECTED_HOSTS=()

KEY_NAME=""
KEY_JSON=""

die() { echo "error: $*" >&2; exit 1; }
note() { echo "• $*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

authorize() {
  [[ -n "$TOKEN" ]] || TOKEN="$(gcloud auth print-access-token)" \
    || die "gcloud auth print-access-token failed; run 'gcloud auth login'"
}

http_get() {
  curl -sS --fail-with-body -H "Authorization: Bearer $TOKEN" "$1"
}

http_patch() {
  curl -sS --fail-with-body -X PATCH \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$2" "$1"
}

# The browser (web) API key from the generated Firebase web config.
web_api_key() {
  [[ -f "$FIREBASE_OPTIONS" ]] || die "not found: $FIREBASE_OPTIONS (is this the repo?)"
  local line key
  line="$(awk '/FirebaseOptions web/{f=1} f && /apiKey:/{print; exit}' "$FIREBASE_OPTIONS")"
  key="$(sed -E "s/.*apiKey:[[:space:]]*'([^']+)'.*/\1/" <<<"$line")"
  [[ "$key" =~ ^AIza[0-9A-Za-z_-]{35}$ ]] || die "could not parse the web apiKey from $FIREBASE_OPTIONS"
  printf '%s' "$key"
}

# Locate the API Keys API key whose keyString matches the web apiKey, following
# pagination and skipping keys the caller cannot read. Sets KEY_NAME and KEY_JSON.
# Returns 0 on match, 1 on no match, 2 on a failed API call.
find_key() {
  local wk page token pt name json ks
  wk="$(web_api_key)" || return 2
  token=""
  while :; do
    local url="$API/projects/$PROJECT_ID/locations/global/keys?pageSize=200"
    if [[ -n "$token" ]]; then
      pt="$(jq -rn --arg t "$token" '$t|@uri')"
      url+="&pageToken=$pt"
    fi
    page="$(http_get "$url")" || return 2
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      if ! json="$(http_get "$API/$name")"; then
        note "skipping unreadable key: $name"
        continue
      fi
      ks="$(jq -r '.keyString // empty' <<<"$json")"
      if [[ "$ks" == "$wk" ]]; then
        KEY_NAME="$name"
        KEY_JSON="$json"
        return 0
      fi
    done < <(jq -r '.keys[]?.name' <<<"$page")
    token="$(jq -r '.nextPageToken // empty' <<<"$page")"
    [[ -n "$token" ]] || break
  done
  return 1
}

find_key_or_die() {
  local rc=0
  find_key || rc=$?
  case "$rc" in
    0) : ;;
    1) die "no API key matched the web apiKey in firebase_options.dart" ;;
    *) die "listing API keys failed (check credentials and permissions)" ;;
  esac
}

# Set-math helpers. They preserve existing order and never re-sort.
add_entry() { jq -c --arg e "$1" 'if index($e) then . else . + [$e] end'; }
del_entry() { jq -c --arg e "$1" 'map(select(. != $e))'; }

print_google_add() {
  cat <<EOF

  Google sign-in needs one more list, which has no public API:
    Google Cloud Console -> APIs & Services -> Credentials
      -> the web OAuth 2.0 client ("Web client (auto created by Google Service)")
      -> Authorized JavaScript origins -> Add URI ->  https://$1

EOF
}

print_google_remove() {
  cat <<EOF

  Remember to remove the matching Google OAuth origin by hand (no public API):
    Google Cloud Console -> APIs & Services -> Credentials
      -> the web OAuth 2.0 client ("Web client (auto created by Google Service)")
      -> Authorized JavaScript origins -> delete  https://$1

EOF
}

print_google_step() {
  if [[ "$1" == add ]]; then print_google_add "$2"; else print_google_remove "$2"; fi
}

cmd_list() {
  authorize
  echo "== Firebase Auth authorized domains (project $PROJECT_ID) =="
  http_get "$ITK/projects/$PROJECT_ID/config" | jq -r '.authorizedDomains[]?'
  echo
  echo "== Browser API key HTTP referrers =="
  find_key_or_die
  jq -r '"browserKeyRestrictions: \(if .restrictions.browserKeyRestrictions == null then "absent (add will refuse)" else "present" end)\napiTargets: \(.restrictions.apiTargets // [] | join(", ") | if . == "" then "none" else . end)\nreferrers:\n" + ([.restrictions.browserKeyRestrictions.allowedReferrers[]?] | join("\n"))' \
    <<<"$KEY_JSON"
}

mutate() {
  local mode="$1" host="$2" flag="${3:-}"
  authorize
  find_key_or_die

  local key_json="$KEY_JSON" entry etag
  entry="https://$host/*"
  etag="$(jq -er '.etag // empty' <<<"$key_json")" \
    || die "the API key response has no etag; refusing to PATCH"

  # For `add`, refuse to invent a restriction on an unrestricted key: PATCHing
  # allowedReferrers onto a key that has none would lock out EVERY other origin
  # (live, previews, localhost) — a production outage from a "safe" helper.
  if [[ "$mode" == add ]] && ! jq -e '.restrictions.browserKeyRestrictions != null' >/dev/null <<<"$key_json"; then
    die "the browser API key has no HTTP-referrer restriction yet; refusing to create one (that would reject every other origin). Configure referrers in the console first."
  fi

  local cur_refs new_refs cur_domains new_domains cfg
  cur_refs="$(jq -c '.restrictions.browserKeyRestrictions.allowedReferrers // []' <<<"$key_json")"
  case "$mode" in
    add)    new_refs="$(add_entry "$entry" <<<"$cur_refs")" ;;
    remove) new_refs="$(del_entry "$entry" <<<"$cur_refs")" ;;
  esac

  cfg="$(http_get "$ITK/projects/$PROJECT_ID/config")"
  cur_domains="$(jq -c '.authorizedDomains // []' <<<"$cfg")"
  case "$mode" in
    add)    new_domains="$(add_entry "$host" <<<"$cur_domains")" ;;
    remove) new_domains="$(del_entry "$host" <<<"$cur_domains")" ;;
  esac

  local refs_changed=no domains_changed=no
  [[ "$new_refs" == "$cur_refs" ]] || refs_changed=yes
  [[ "$new_domains" == "$cur_domains" ]] || domains_changed=yes

  if [[ "$refs_changed" == yes && "$mode" == remove && "$new_refs" == "[]" ]]; then
    die "refusing to write an empty referrer list (that would reject every origin). Remove the last referrer in the console instead."
  fi

  if [[ "$refs_changed" == no && "$domains_changed" == no ]]; then
    if [[ "$mode" == add ]]; then
      note "no change: $host is already allowlisted"
    else
      note "no change: $host is already absent"
    fi
    print_google_step "$mode" "$host"
    return 0
  fi

  local ref_body
  ref_body="$(jq -cn --arg etag "$etag" --argjson refs "$new_refs" \
    --argjson targets "$(jq -c '.restrictions.apiTargets // []' <<<"$key_json")" \
    '{etag: $etag, restrictions: {browserKeyRestrictions: {allowedReferrers: $refs}, apiTargets: $targets}}')"

  if [[ "$refs_changed" == yes ]]; then
    echo "Planned browser API key PATCH (updateMask=restrictions.browserKeyRestrictions.allowedReferrers):"
    jq . <<<"$ref_body"
  else
    echo "Browser API key referrers: unchanged."
  fi
  if [[ "$domains_changed" == yes ]]; then
    echo "Planned Auth authorizedDomains: $new_domains"
  else
    echo "Auth authorizedDomains: unchanged."
  fi

  if [[ "$flag" != "--apply" ]]; then
    note "dry run: Firebase not modified. Re-run with --apply to write."
    print_google_step "$mode" "$host"
    return 0
  fi

  mkdir -p "$BACKUP_DIR"
  local backup
  backup="$BACKUP_DIR/state-$(date -u +%Y%m%dT%H%M%SZ)-$$.json"
  jq -n --argjson key "$key_json" \
    --argjson auth "$(jq -c '.authorizedDomains // []' <<<"$cfg")" \
    '{key: $key, authorizedDomains: $auth}' > "$backup"
  note "backup written: $backup"

  # Auth domains first (no etag, simpler); if this fails nothing is written below.
  if [[ "$domains_changed" == yes ]]; then
    # Re-read to fail closed if another writer (e.g. a channel deploy) changed the list.
    local cfg2
    cfg2="$(http_get "$ITK/projects/$PROJECT_ID/config")"
    [[ "$(jq -c '.authorizedDomains // []' <<<"$cfg2")" == "$cur_domains" ]] \
      || die "Auth authorized domains changed while working; nothing was written. Re-run."

    local out
    if ! out="$(http_patch "$ITK/projects/$PROJECT_ID/config?updateMask=authorizedDomains" \
        "$(jq -cn --argjson d "$new_domains" '{authorizedDomains: $d}')")"; then
      note "server response: $out"
      die "updating Auth authorized domains failed; nothing was written to the API key."
    fi
    note "Auth authorized domains updated for $host"
  fi

  if [[ "$refs_changed" == yes ]]; then
    local out
    if ! out="$(http_patch "$API/$KEY_NAME?updateMask=restrictions.browserKeyRestrictions.allowedReferrers" "$ref_body")"; then
      note "server response: $out"
      die "the browser API key PATCH failed; Auth domains may already be updated. Revert with: preview-auth.sh remove $host --apply (backup: $backup)"
    fi
    note "browser API key referrers updated"
  fi

  print_google_step "$mode" "$host"
  return 0
}

resolve_guard() {
  [[ -n "$PROJECT_ID" ]] || PROJECT_ID="$(jq -r '.projects.default // empty' "$REPO_ROOT/.firebaserc")"
  [[ "$PROJECT_ID" =~ ^[a-z0-9][a-z0-9-]{4,28}[a-z0-9]$ ]] \
    || die "invalid or missing PROJECT_ID: '$PROJECT_ID' (from .firebaserc projects.default)"
  HOST_REGEX="^(${PROJECT_ID}|wish-together-staging)(--[A-Za-z0-9-]+)?\\.web\\.app$"
  PROTECTED_HOSTS=(
    "${PROJECT_ID}.web.app"
    "${PROJECT_ID}.firebaseapp.com"
    "wish-together-staging.web.app"
    "wishtogether.gift"
    "www.wishtogether.gift"
    "localhost"
  )
}

main() {
  local cmd="${1:-}"; shift || true
  local host="${1:-}" flag="${2:-}"
  [[ -z "${3:-}" ]] || die "unexpected extra argument: ${3}"

  case "$cmd" in
    list)
      [[ -z "$host$flag" ]] || die "list takes no arguments"
      ;;
    add|remove)
      [[ -n "$host" ]] || die "usage: preview-auth.sh $cmd <host> [--apply]"
      [[ "$flag" == "" || "$flag" == "--apply" ]] || die "unknown option: '$flag' (only --apply is accepted)"
      ;;
    *) die "usage: preview-auth.sh {list|add <host>|remove <host>} [--apply]" ;;
  esac

  need curl; need jq
  resolve_guard

  if [[ "$cmd" != "list" ]]; then
    [[ "$host" =~ $HOST_REGEX ]] \
      || die "refusing '$host': not a Firebase Hosting host of project $PROJECT_ID (expected <project>--<channel>-<id>.web.app or wish-together-staging.web.app)"
    if [[ "$cmd" == remove ]]; then
      local p
      for p in "${PROTECTED_HOSTS[@]}"; do
        [[ "$host" == "$p" ]] && die "refusing to remove protected host: $p"
      done
    fi
  fi

  [[ -n "$TOKEN" ]] || need gcloud

  case "$cmd" in
    list)   cmd_list ;;
    add)    mutate add "$host" "$flag" ;;
    remove) mutate remove "$host" "$flag" ;;
  esac
}

if [[ "${BASH_SOURCE[0]:-$0}" == "$0" ]]; then
  main "$@"
fi
