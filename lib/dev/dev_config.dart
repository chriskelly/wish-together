/// Compile-time switches for a development session.
library;

import 'package:wishtogether/core/firestore_target.dart';

/// The query parameter that selects a committed scenario.
const String devScenarioParam = 'scenario';

/// The scenario used when neither the URL nor the define names one.
const String defaultScenarioId = 'default';

/// The backend that runs entirely in memory.
const String fakeDevBackend = 'fake';

/// The backend that signs in for real against a named Firestore database.
const String liveDevBackend = 'live';

/// The scenario id compiled into the build, used when the URL names none.
const String devScenarioDefine = String.fromEnvironment('WT_DEV_SCENARIO');

/// The backend compiled into the build.
const String devBackendDefine = String.fromEnvironment('WT_DEV_BACKEND');

/// The custom token compiled into the build, read only by the live backend.
///
/// It is a bearer credential for one uid and lasts about an hour. It arrives
/// through `--dart-define`, so it is visible inside a debug bundle; it is a
/// development credential for a named database and never a production one.
const String devTokenDefine = String.fromEnvironment('WT_DEV_TOKEN');

/// The port a live session must be served on.
///
/// The project's browser API key restricts HTTP referrers, and the only
/// localhost entry it allows is `http://localhost:59922/*` (checked with
/// `.agents/skills/preview-auth/scripts/preview-auth.sh list`). A live sign-in
/// from any other port is rejected by the API key, not by Firebase Auth, so the
/// mint script pins this port in the command it prints. `scripts/dev-token.mjs`
/// carries the same number; `test/dev/dev_live_test.dart` fails if they drift.
const int devLiveWebPort = 59922;

/// The literal a development build carries and a production build never does.
///
/// The CI bundle guard searches the compiled `main.dart.js` for this string, so
/// it is the marker a dev artifact is recognised by. It is deliberately a
/// stable literal rather than a version: the guard outlives the code.
const String devBundleMarker = 'wishtogether-dev-session';

/// The scenario to show: the URL wins, then the compiled default.
///
/// A blank value on either side is treated as absent: an empty `?scenario=` is
/// what a tool leaves behind when it has nothing to say, not a request for a
/// scenario named "". An id that is neither blank nor known fails later, in
/// the registry, rather than here.
String resolveScenarioId({
  String? urlScenario,
  String defineScenario = devScenarioDefine,
}) {
  final fromUrl = urlScenario?.trim() ?? '';
  if (fromUrl.isNotEmpty) {
    return fromUrl;
  }
  final fromDefine = defineScenario.trim();
  if (fromDefine.isNotEmpty) {
    return fromDefine;
  }
  return defaultScenarioId;
}

/// The scenario named by [uri]'s query, falling back to the compiled default.
///
/// The page URL is the only runtime input a dev session has; everything else
/// comes from the path go_router already routes on.
String scenarioIdFor(Uri uri, {String defineScenario = devScenarioDefine}) =>
    resolveScenarioId(
      urlScenario: uri.queryParameters[devScenarioParam],
      defineScenario: defineScenario,
    );

/// What a dev entrypoint should do.
///
/// Resolving this is the entrypoint's only decision, and every outcome is a
/// value: a launch that cannot run is something the entrypoint can render,
/// because a failure thrown before `runApp` leaves a blank browser tab whose
/// only trace is a console error nobody may be reading.
sealed class DevLaunch {
  const DevLaunch();
}

/// A session over the in-memory store, showing [scenarioId].
final class FakeDevLaunch extends DevLaunch {
  const FakeDevLaunch(this.scenarioId);

  /// The committed scenario the registry resolves to a fixture.
  final String scenarioId;
}

/// A session signed in for real against [databaseId].
final class LiveDevLaunch extends DevLaunch {
  const LiveDevLaunch({
    required this.databaseId,
    required this.token,
    this.ignoredScenario,
  });

  /// The named Firestore database. Never `(default)`: that is production.
  final String databaseId;

  /// The custom token to sign in with.
  final String token;

  /// The `?scenario=` the URL asked for, which live mode ignores.
  ///
  /// Live data has no scenario. Carrying the request here is what lets the
  /// banner say it was ignored, instead of staging data being read as a
  /// fixture.
  final String? ignoredScenario;
}

/// A launch that cannot run, and why.
final class RefusedDevLaunch extends DevLaunch {
  const RefusedDevLaunch({required this.headline, required this.details});

  /// One line naming what is wrong.
  final String headline;

  /// What to change, in the order a reader should act on it.
  final List<String> details;
}

/// Resolves what this build should run, from its compile-time inputs.
///
/// [urlScenario] is the page URL's `?scenario=`, which only fake mode uses.
///
/// The live branch is the safety boundary: an empty database define means the
/// production database, so it is refused rather than treated as "no override".
/// Each refusal names the input and the command that supplies it, because the
/// page it becomes is the only thing a reader has.
DevLaunch resolveDevLaunch({
  String backendDefine = devBackendDefine,
  String databaseDefine = firestoreDatabaseIdOverride,
  String tokenDefine = devTokenDefine,
  String? urlScenario,
  String defineScenario = devScenarioDefine,
}) {
  final backend = backendDefine.trim();
  switch (backend) {
    case '':
    case fakeDevBackend:
      return FakeDevLaunch(
        resolveScenarioId(
          urlScenario: urlScenario,
          defineScenario: defineScenario,
        ),
      );
    case liveDevBackend:
      return _resolveLiveLaunch(
        databaseDefine: databaseDefine,
        tokenDefine: tokenDefine,
        urlScenario: urlScenario,
      );
    default:
      return RefusedDevLaunch(
        headline:
            'WT_DEV_BACKEND="$backend" is not a backend this build can run',
        details: <String>[
          'Use "$fakeDevBackend" (or leave it unset) for the in-memory session, '
              'or "$liveDevBackend" for a real session against a named database.',
          'The backend is compiled in, so change the --dart-define and restart.',
        ],
      );
  }
}

/// The live launch, or the refusal that keeps it off production.
///
/// The database is checked before the token on purpose: the database is the
/// production boundary, and a reader should fix that first.
DevLaunch _resolveLiveLaunch({
  required String databaseDefine,
  required String tokenDefine,
  required String? urlScenario,
}) {
  final rawDatabase = databaseDefine.trim();
  if (rawDatabase.isEmpty) {
    return const RefusedDevLaunch(
      headline: 'Live dev mode needs a named database',
      details: <String>[
        'WT_DEV_BACKEND=live refuses to start without WT_FIRESTORE_DATABASE, '
            'because an empty value means the production database.',
        'Mint a token and get the exact command: '
            'cd scripts && npm run dev:token -- --uid <uid>',
        'That command sets WT_FIRESTORE_DATABASE to a named database such as '
            '"staging".',
      ],
    );
  }

  final String databaseId;
  try {
    databaseId = resolveFirestoreDatabaseId(rawDatabase);
  } on ArgumentError {
    return RefusedDevLaunch(
      headline: 'WT_FIRESTORE_DATABASE="$rawDatabase" is not a database id',
      details: const <String>[
        'A Firestore database id is lowercase, starts with a letter and is 4 to '
            '63 characters, for example "staging".',
        'npm run dev:token prints the whole command with a valid id.',
      ],
    );
  }

  if (databaseId == defaultFirestoreDatabaseId) {
    return const RefusedDevLaunch(
      headline: 'Live dev mode refuses the production database',
      details: <String>[
        'WT_FIRESTORE_DATABASE="(default)" is the production database.',
        'Name the staging database instead: '
            '--dart-define=WT_FIRESTORE_DATABASE=staging',
        'npm run dev:token prints the whole command.',
      ],
    );
  }

  final token = tokenDefine.trim();
  if (token.isEmpty) {
    return RefusedDevLaunch(
      headline: 'Live dev mode needs a token',
      details: <String>[
        'WT_DEV_TOKEN is empty.',
        'cd scripts && npm run dev:token -- --uid <uid> --database $databaseId '
            'prints a fresh token and the whole flutter run line.',
        'Tokens last about an hour, and a new one needs a restart: '
            '--dart-define is compile-time.',
      ],
    );
  }

  final requested = urlScenario?.trim() ?? '';
  return LiveDevLaunch(
    databaseId: databaseId,
    token: token,
    ignoredScenario: requested.isEmpty ? null : requested,
  );
}
