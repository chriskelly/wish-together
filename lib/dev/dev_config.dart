/// Compile-time switches for a development session.
library;

/// The query parameter that selects a committed scenario.
const String devScenarioParam = 'scenario';

/// The scenario used when neither the URL nor the define names one.
const String defaultScenarioId = 'default';

/// The backend that runs entirely in memory.
const String fakeDevBackend = 'fake';

/// The scenario id compiled into the build, used when the URL names none.
const String devScenarioDefine = String.fromEnvironment('WT_DEV_SCENARIO');

/// The backend compiled into the build.
const String devBackendDefine = String.fromEnvironment('WT_DEV_BACKEND');

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

/// Rejects any backend this build cannot run.
///
/// Only the fake backend exists today: it needs no Firebase, no credentials and
/// no network. An unknown backend stops the launch instead of quietly rendering
/// an empty fake session, because an agent must never mistake the wrong backend
/// for the real one.
void requireFakeBackend(String raw) {
  final backend = raw.trim();
  if (backend.isEmpty || backend == fakeDevBackend) {
    return;
  }
  throw StateError(
    'WT_DEV_BACKEND="$backend" is not supported by this build. Only '
    '"$fakeDevBackend" runs without Firebase; live mode is not implemented yet.',
  );
}
