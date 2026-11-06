# Dev sessions — Agent Guide

A development entrypoint that boots the app **signed in**, on the real widgets, against an
in-memory fixture (the default) or real Firebase on a named database. It exists so an agent or
the user can see, drive and screenshot any signed-in screen without a deployment.

Paths here are relative to `lib/dev/`, then to the repository root.

## Rules

- `lib/main.dart` never imports anything under `lib/dev/`, and no production bundle contains
  the fake store. `test/dev/no_dev_in_production_test.dart` walks the import graph.
- Fake mode never touches a real Firebase singleton. `live_dev_session.dart` is the only file
  allowed to do so; never widen that list.
- A fixture must not read the clock, and must seed a `users/<uid>` document with a display name
  for its viewer, or every route redirects to onboarding.
- A private fixture lives under `lib/dev/scenarios/local/`, which is gitignored and imported by
  nothing else; keep it that way so a fresh clone compiles.

## Reference

- What runs, the layout, the scenarios and how to find their ids → `docs/scenarios.md`
- Running the fake backend and authoring a fixture → `docs/fake-mode.md`
- Real Auth and Firestore on the staging database → `docs/live-mode.md`
- What a fake-mode success does not prove, accessible names, boundaries → `docs/limits.md`
