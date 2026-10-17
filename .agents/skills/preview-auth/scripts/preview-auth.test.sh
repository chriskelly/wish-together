#!/usr/bin/env bash
#
# Tests for preview-auth.sh. No network: curl and gcloud are stubbed on PATH, and
# the API responses are local fixtures. Run from anywhere inside the repo:
#
#   bash .agents/skills/preview-auth/scripts/preview-auth.test.sh
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/preview-auth.sh"

pass=0
fail=0
ok() { echo "ok   - $1"; pass=$((pass + 1)); }
no() { echo "FAIL - $1"; fail=$((fail + 1)); }
eq() { if [[ "$1" == "$2" ]]; then ok "$3"; else no "$3 (got '$1', want '$2')"; fi; }

# ---- stub curl / gcloud ----
STUB="$(mktemp -d)"
trap 'rm -rf "$STUB" "${OPT:-}"' EXIT
cat > "$STUB/gcloud" <<'EOF'
#!/usr/bin/env bash
echo "stub-token"
EOF
cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$CURL_LOG"
case "$*" in
  *"/locations/global/keys?pageSize"*) printf '%s' "$CURL_LIST" ;;
  *"/locations/global/keys/"*)          printf '%s' "$CURL_GET" ;;
  *) printf '%s' '{}' ;;
esac
EOF
chmod +x "$STUB/gcloud" "$STUB/curl"
export PATH="$STUB:$PATH"

# ---- fixtures ----
WEB_KEY="AIzaSyA7hcyTmnUkeyO_tREyxb1pYGw0ZKDE2jg" # shape only; not a real credential
OPT="$(mktemp)"
printf "static const FirebaseOptions web = FirebaseOptions(\n  apiKey: '%s',\n);\n" "$WEB_KEY" > "$OPT"
export CURL_LOG; CURL_LOG="$(mktemp)"; : > "$CURL_LOG"
export CURL_LIST='{"keys":[{"name":"projects/wish-together-project/locations/global/keys/k1"}]}'
export CURL_GET="{\"keyString\":\"$WEB_KEY\",\"etag\":\"etag-1\",\"restrictions\":{\"browserKeyRestrictions\":{\"allowedReferrers\":[\"https://a/*\"]}}}"

# ---- source the script for the pure-unit tests ----
# shellcheck source=/dev/null
source "$SCRIPT"
set +eu

# ---- set math (order-preserving, idempotent) ----
eq "$(add_entry 'https://x/*' <<<'["https://z/*","https://a/*"]')" '["https://z/*","https://a/*","https://x/*"]' "add_entry appends, preserving order"
eq "$(add_entry 'https://a/*' <<<'["https://z/*","https://a/*"]')" '["https://z/*","https://a/*"]' "add_entry is idempotent (no reorder)"
eq "$(del_entry 'https://a/*' <<<'["https://z/*","https://a/*"]')" '["https://z/*"]' "del_entry removes the entry"
eq "$(del_entry 'https://nope/*' <<<'["https://z/*"]')" '["https://z/*"]' "del_entry of an absent entry is a no-op"

# ---- find_key builds a FULL API URL (regression: http_get needs the base) ----
export PROJECT_ID="wish-together-project"
export TOKEN="stub-token"
export FIREBASE_OPTIONS="$OPT"
: > "$CURL_LOG"
if find_key >/dev/null 2>&1; then
  eq "$(jq -r '.keyString' <<<"$KEY_JSON")" "$WEB_KEY" "find_key matches the web key by keyString"
else
  no "find_key returned non-zero with a valid stub response"
fi
if grep -q "https://apikeys.googleapis.com/v2/projects/wish-together-project/locations/global/keys" "$CURL_LOG"; then
  ok "find_key requests a full API Keys URL"
else
  no "find_key URL is missing the API base: $(head -1 "$CURL_LOG")"
fi
if grep -q "keys/k1" "$CURL_LOG"; then ok "find_key GETs the candidate key"; else no "find_key did not GET the key"; fi

# ---- guards (run the real script as a subprocess) ----
expect_die() {
  local want="$1"; shift
  local out
  out="$(bash "$SCRIPT" "$@" 2>&1)"
  if [[ "$out" == *"$want"* ]]; then ok "$* -> refused"; else no "$* -> expected '$want', got '$out'"; fi
}
expect_die "refusing 'evil.com'" add evil.com
expect_die "not a Firebase Hosting host" add wishtogether.gift
expect_die "protected host" remove wish-together-staging.web.app
expect_die "unknown option" add wish-together-project--pr-12-abc.web.app --aply
expect_die "unexpected extra argument" add a b c
expect_die "list takes no arguments" list --apply

echo
echo "passed: $pass   failed: $fail"
[[ "$fail" -eq 0 ]]
