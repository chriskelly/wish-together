# Live mode

Scope: signing a dev session in against real Auth and the staging Firestore
database, its refusals, and the one port it can use. Read before a rules
rehearsal or any check the fake cannot enforce. Paths are relative to
`lib/dev/`, then to the repository root.

Live mode signs in for real, so it is the check for everything the fake cannot enforce: security
rules, composite indexes, server timestamps, cross-client real-time fan-out, and the shape of real
data. It is also the only mode that runs the real `AuthService` — the uid stream, the providers and
sign-out are production's own. Account deletion does not: see below.

## Running it

```sh
GOOGLE_APPLICATION_CREDENTIALS=... tool/dev.sh live --uid <uid> --database staging
```

The runner mints the token itself and pins port 59922. The raw command:

```sh
flutter run -t lib/dev/dev_main.dart -d chrome --web-port=59922 \
  --dart-define=WT_DEV_BACKEND=live \
  --dart-define=WT_FIRESTORE_DATABASE=staging \
  --dart-define=WT_DEV_TOKEN=<token from `cd scripts && npm run dev:token`>
```

| Input | Effect |
| ----- | ------ |
| `--dart-define=WT_DEV_BACKEND=` | `live` for the real backend; anything else is a page naming both |
| `--dart-define=WT_FIRESTORE_DATABASE=<id>` | the named database. Empty means production and is refused, as is `(default)` |
| `--dart-define=WT_DEV_TOKEN=<token>` | the custom token from `cd scripts && npm run dev:token` |
| `--dart-define=WT_DEV_ALLOW_ACCOUNT_DELETION=true` | offers account deletion, which is otherwise hidden |
| `--web-port=59922` | the port the project's API key allows |

Mint a token (the same service account `seed-demo` uses):

```sh
cd scripts && npm ci
GOOGLE_APPLICATION_CREDENTIALS=~/path/to/service-account.json \
  npm run dev:token -- --uid <uid> --database staging
```

It prints the token and the whole `flutter run` line — one line, with the port pinned. The uid
needs no Auth account: the first sign-in creates one. Seed what it should see with the same uid,
and remove it afterwards (see `docs/staging.md`).

**It cannot reach production.** The launch is resolved before Firebase is touched, and each
refusal is its own page. They are decided in one fixed order: the backend first, then the database
(empty, then production, then a malformed id), then the token, then the account-deletion flag. The
first failure in that order is the page a reader gets, so a bad backend is reported as a bad
backend even when the database is wrong too.

| Refusal page | Cause |
| ------------ | ----- |
| `WT_DEV_BACKEND="<value>" is not a backend this build can run` | anything other than `fake` or `live`; checked first |
| `Live dev mode needs a named database` | `WT_FIRESTORE_DATABASE` is unset or blank, which means the production database |
| `Live dev mode refuses the production database` | `WT_FIRESTORE_DATABASE="(default)"` |
| `WT_FIRESTORE_DATABASE="<value>" is not a database id` | malformed id (lowercase, 4–63 characters, starts with a letter) |
| `Live dev mode needs a token` | `WT_DEV_TOKEN` is unset or blank |
| `WT_DEV_ALLOW_ACCOUNT_DELETION="<value>" is not a flag value` | anything other than `true`, `false` or unset; the value is trimmed first, so `" true "` enables deletion |
| `Live dev mode could not sign in` | the token expired or was rejected, or the page's origin is not one the project API key allows; names `npm run dev:token` and the port |
| `Live dev mode could not start` | `initializeApp`, or the session built on it, failed |

A token lasts about an hour. `--dart-define` is compile-time, so a fresh token means stopping the
app and running the line again — a hot restart keeps the old one.

While the token is exchanged the page is a notice (`Live dev mode is signing in`, on the `starting`
strip), so the window before the session exists is never a blank tab. It is replaced by the app, or
by the reason the sign-in failed.

**The port is not free choice.** The project's browser API key restricts HTTP referrers, and the
only localhost entry it allows is `http://localhost:59922/*`, so live sign-in works on
`--web-port=59922` and no other. Any other port fails at sign-in with an API-key error, which the
failure page names. `.agents/skills/preview-auth/scripts/preview-auth.sh list` prints the allowed
referrers. Two concurrent sessions (the only way to see cross-client behaviour) would need a second
port added to that key, which is an operator change, not something this harness does.

## Account deletion and sign-out

**Account deletion is off unless the build asks for it.** The live session is a real `AuthService`
with one capability removed, so the profile page has no danger zone: the cascade re-authenticates
against the real provider and then deletes a real Auth user, and this Auth project is shared with
production. To exercise that flow on purpose, add `--dart-define=WT_DEV_ALLOW_ACCOUNT_DELETION=true`
— and only ever with a synthetic uid, because the account it deletes is the one it signed in as.

**Sign-out really signs out.** The home page's Logout control ends the session and returns to the
login page, which builds here (the real `AuthService` is registered) but cannot sign back in from
localhost, because no OAuth origin is allowlisted for it. Getting back into a live session means a
new token and a restart.

App Check is not activated by this path, the update gate is not part of it (so a production
`min_supported_build` cannot block a live session), and Sentry is not initialised.

**Which rules apply.** Live mode runs against whatever ruleset is currently deployed to the named
database. `npm run rules:release -- show --database staging` prints it; dispatch the staging deploy
to rehearse a candidate ruleset first.
