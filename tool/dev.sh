#!/usr/bin/env bash
#
# One command per dev-session backend.
#
#   tool/dev.sh                                  fake, scenario "default", headless
#   tool/dev.sh family /wishlist/fam-l1          fake, scenario and deep page
#   tool/dev.sh live --uid <uid>                 real Auth + Firestore, staging
#
# The fake backend is served headless (`-d web-server`) so the printed URL is the
# thing to open; `--chrome` launches a browser at the same URL. Arguments after
# `--` are passed through to `flutter run`.
#
# The scenario ids are read from the committed fixture modules, so a new scenario
# needs no change here.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Headless fake sessions need a fixed port, or the printed URL would be a guess.
# 47923 is deliberately not one of the usual development ports (3000, 5000,
# 8080) and is not the live port: the project's browser API key pins live mode to
# 59922. Pass --port to move the fake one.
readonly fake_port=47923
readonly live_port=59922

entrypoint="lib/dev/dev_main.dart"
entrypoint_set=0
backend="fake"
uid=""
database="staging"
database_set=0
chrome=0
port=""
allow_deletion=0
positional_args=()
passthrough=()

die() {
  echo "tool/dev.sh: $*" >&2
  exit 2
}

usage() {
  cat <<'EOF'
Usage:
  tool/dev.sh [scenario] [path] [--chrome] [--port <port>] [-- <flutter args>]
  tool/dev.sh --entrypoint <file> [path] [--chrome] [--port <port>] [-- <flutter args>]
  tool/dev.sh live [path] --uid <uid> [--database <id>] [--chrome] [-- <flutter args>]

Fake backend (default)
  Boots the app signed in over an in-memory Firestore seeded from a Dart
  fixture. No credentials, no network. Served headless on port 47923 unless
  --port moves it; the URL to open is printed before the server starts.

  scenario   one of the committed ids (default: "default"); a lone argument
             beginning with "/" is read as the path instead
  path       the route to start on, must begin with "/" (default: "/")

Live backend
  Boots the app signed in for real against a named Firestore database. Mints a
  custom token with scripts/dev-token.mjs, so GOOGLE_APPLICATION_CREDENTIALS
  must point at the project's service-account JSON and scripts/node_modules
  must exist (cd scripts && npm ci). Always served on port 59922: it is the
  only localhost origin the project's browser API key allows.

  --uid <uid>            the account to sign in as (required; use a synthetic
                         one with --allow-account-deletion)
  --database <id>        a named database (default: staging). "(default)" and
                         an empty value are refused.

Options
  --chrome               launch Chrome at the printed URL instead of serving
                         headless
  --port <port>          fake only, except the pinned 59922 in live: the port to
                         serve the fake session on (default: 47923)
  --entrypoint <file>    fake only: a one-off entrypoint to run instead of the
                         committed one, e.g. lib/dev/scenarios/local/mine.dart
  --allow-account-deletion
                         live only: offers account deletion in the profile page.
                         It deletes a real Auth account and staging shares
                         production Auth, so only use a synthetic uid.
  -h, --help             print this message

The scenario is read from the entry URL once. Reloading switches a committed
scenario and re-seeds the fixture; a one-off entrypoint needs a restart.
EOF
}

# The ids the committed fixture modules declare, one per module in the ordinary
# case. Each module keeps its id as a quoted literal (`id: 'default'`); if a
# module stops doing that, the count below notices and the app's own
# unknown-scenario page names the ids instead of a stale list.
committed_scenarios() {
  local files=()
  local ids
  files=(lib/dev/fixtures/*_scenario.dart)
  ids="$(
    grep -hoE "^[[:space:]]{2}id: ['\"][^'\"]+['\"]" "${files[@]}" \
      | sed -E "s/^[[:space:]]*id: ['\"]//; s/['\"]$//" \
      | sort -u
  )"
  if [[ -z "$ids" ]]; then
    die "could not read a scenario id from lib/dev/fixtures/*_scenario.dart"
  fi
  printf '%s\n' "$ids"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --chrome)
      chrome=1
      shift
      ;;
    --allow-account-deletion)
      allow_deletion=1
      shift
      ;;
    --port)
      [[ $# -ge 2 ]] || die "--port needs a value"
      port="$2"
      shift 2
      ;;
    --entrypoint)
      [[ $# -ge 2 ]] || die "--entrypoint needs a value"
      entrypoint="$2"
      entrypoint_set=1
      shift 2
      ;;
    --uid)
      [[ $# -ge 2 ]] || die "--uid needs a value"
      uid="$2"
      shift 2
      ;;
    --database)
      [[ $# -ge 2 ]] || die "--database needs a value"
      database="$2"
      database_set=1
      shift 2
      ;;
    --)
      shift
      passthrough=("$@")
      break
      ;;
    -*)
      die "unknown option \"$1\" (try --help)"
      ;;
    *)
      positional_args+=("$1")
      shift
      ;;
  esac
done

command -v flutter >/dev/null 2>&1 || die "flutter is not on PATH"

# `live` is the backend selector, not a scenario id. Reserved because the
# registry has no scenario by that name.
if [[ ${#positional_args[@]} -gt 0 && "${positional_args[0]}" == "live" ]]; then
  backend="live"
  positional_args=("${positional_args[@]:1}")
fi

# One route, in either backend: a path the browser opens directly. A query is
# refused because the scenario belongs in the runner's own argument, not in a
# second place that can disagree with the banner.
validate_route() {
  local route="$1"
  [[ "$route" == /* ]] \
    || die "the path must start with \"/\" (got \"$route\")"
  [[ "$route" != *\?* && "$route" != *"#"* ]] \
    || die "the path is only the route (no query or fragment)"
}

if [[ "$backend" == "live" ]]; then
  [[ ${#positional_args[@]} -le 1 ]] \
    || die "live mode takes at most one path (got ${#positional_args[@]} arguments)"
  [[ "$entrypoint_set" -eq 0 ]] \
    || die "--entrypoint is fake-mode only; live uses the committed entrypoint"
  if [[ -n "$port" && "$port" != "$live_port" ]]; then
    die "live mode is always port $live_port (got \"$port\"); drop --port"
  fi
  [[ -n "$uid" ]] || die "live mode needs --uid <uid> (use a synthetic one)"
  [[ -n "$database" ]] || die "live mode needs a named database (default: staging)"
  [[ "$database" != "(default)" ]] \
    || die "--database \"(default)\" is the production database; live mode refuses it"
  [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]] \
    || die "live mode needs GOOGLE_APPLICATION_CREDENTIALS pointing at the project's service-account JSON"
  [[ -d scripts/node_modules/firebase-admin ]] \
    || die "live mode needs scripts dependencies; run: cd scripts && npm ci"
  command -v npm >/dev/null 2>&1 || die "npm is not on PATH"

  route="/"
  if [[ ${#positional_args[@]} -eq 1 ]]; then
    route="${positional_args[0]}"
    validate_route "$route"
  fi

  # The mint script prints warnings (an existing uid, a bad port) to stderr, so
  # let those through; stdout holds the token and a ready-to-paste command that
  # this script replaces. The token is not echoed again.
  if ! mint_output="$(
    npm --prefix scripts run --silent dev:token -- \
      --uid "$uid" --database "$database"
  )"; then
    die "could not mint a live token; see the message above"
  fi
  token="$(
    printf '%s\n' "$mint_output" \
      | grep -E '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' \
      | head -n 1
  )" || true
  [[ -n "$token" ]] \
    || die "could not read a token from scripts/dev-token.mjs; mint one with: cd scripts && npm run dev:token -- --uid $uid --database $database"

  url="http://localhost:$live_port$route"
  device="web-server"
  if [[ "$chrome" -eq 1 ]]; then
    device="chrome"
  fi

  args=(run -t "$entrypoint" -d "$device" "--web-port=$live_port"
    --dart-define=WT_DEV_BACKEND=live
    --dart-define=WT_FIRESTORE_DATABASE="$database"
    --dart-define=WT_DEV_TOKEN="$token")
  if [[ "$chrome" -eq 1 ]]; then
    # `-d chrome` otherwise opens "/", discarding the route.
    args+=("--web-launch-url=$url")
  fi
  if [[ "$allow_deletion" -eq 1 ]]; then
    args+=(--dart-define=WT_DEV_ALLOW_ACCOUNT_DELETION=true)
  fi
  if [[ ${#passthrough[@]} -gt 0 ]]; then
    args+=("${passthrough[@]}")
  fi

  echo "Dev session: live backend, database \"$database\", uid \"$uid\""
  echo "  $url"
  echo "  Data is real; ?scenario is ignored. Auth is the production project, so use a synthetic uid."
  echo "  The token (about an hour) is not printed again."
  exec flutter "${args[@]}"
fi

if [[ "$entrypoint_set" -eq 1 ]]; then
  [[ ${#positional_args[@]} -le 1 ]] \
    || die "with --entrypoint, the only positional argument is the path"
  [[ -z "$uid" ]] || die "--uid is live-only; run: tool/dev.sh live --uid <uid>"
  [[ "$database_set" -eq 0 ]] \
    || die "--database is live-only; run: tool/dev.sh live --uid <uid> --database <id>"
  [[ "$allow_deletion" -eq 0 ]] \
    || die "--allow-account-deletion is live-only; run: tool/dev.sh live --uid <uid> --allow-account-deletion"
  route="/"
  if [[ ${#positional_args[@]} -eq 1 ]]; then
    route="${positional_args[0]}"
    validate_route "$route"
  fi
else
  [[ ${#positional_args[@]} -le 2 ]] \
    || die "expected [scenario] [path] (got ${#positional_args[@]} arguments)"
  scenario="default"
  route="/"
  if [[ ${#positional_args[@]} -eq 1 ]]; then
    # A lone path is the natural way to ask for a deep start.
    if [[ "${positional_args[0]}" == /* ]]; then
      route="${positional_args[0]}"
    else
      scenario="${positional_args[0]}"
    fi
  elif [[ ${#positional_args[@]} -eq 2 ]]; then
    scenario="${positional_args[0]}"
    route="${positional_args[1]}"
  fi
  validate_route "$route"
  [[ -z "$uid" ]] || die "--uid is live-only; run: tool/dev.sh live --uid <uid>"
  [[ "$database_set" -eq 0 ]] \
    || die "--database is live-only; run: tool/dev.sh live --uid <uid> --database <id>"
  [[ "$allow_deletion" -eq 0 ]] \
    || die "--allow-account-deletion is live-only; run: tool/dev.sh live --uid <uid> --allow-account-deletion"

  scenarios="$(committed_scenarios)"
  id_count="$(printf '%s\n' "$scenarios" | grep -c .)"
  file_count="$(printf '%s\n' lib/dev/fixtures/*_scenario.dart | wc -l | tr -d ' ')"
  # Only trust the list when it holds one id per module: a module that spells
  # its id differently makes the list incomplete, and a false "unknown" is worse
  # than launching and letting the app name the ids it has.
  if [[ "$id_count" -ne "$file_count" ]]; then
    echo "tool/dev.sh: note: could not list every scenario ($id_count ids for $file_count modules); the app will name the ids it has" >&2
  elif ! printf '%s\n' "$scenarios" | grep -qxF -- "$scenario"; then
    available="$(printf '%s\n' "$scenarios" | paste -sd ',' - | sed 's/,/, /g')"
    die "unknown scenario \"$scenario\". Available: $available"
  fi
fi

if [[ -n "$port" ]]; then
  [[ "$port" =~ ^[0-9]+$ ]] || die "--port must be a number (got \"$port\")"
  port=$((10#$port))
else
  port="$fake_port"
fi
[[ "$port" -ge 1024 && "$port" -le 65535 ]] \
  || die "--port must be between 1024 and 65535 (got \"$port\")"

url="http://localhost:$port$route"
if [[ "$entrypoint_set" -eq 0 ]]; then
  url="$url?scenario=$scenario"
fi

device="web-server"
if [[ "$chrome" -eq 1 ]]; then
  device="chrome"
fi

args=(run -t "$entrypoint" -d "$device" "--web-port=$port")
if [[ "$chrome" -eq 1 ]]; then
  # `-d chrome` otherwise opens "/", discarding the scenario and the route.
  args+=("--web-launch-url=$url")
fi
if [[ ${#passthrough[@]} -gt 0 ]]; then
  args+=("${passthrough[@]}")
fi

if [[ "$entrypoint_set" -eq 1 ]]; then
  echo "Dev session: entrypoint \"$entrypoint\", fake backend"
else
  echo "Dev session: scenario \"$scenario\", fake backend"
fi
echo "  $url"
echo "  Reload to re-seed or switch scenario; Ctrl-C stops the server."
exec flutter "${args[@]}"
