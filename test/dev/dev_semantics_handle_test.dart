import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/dev/run_dev_session.dart';

/// The dev session's semantics handle, which is load-bearing for every agent
/// that drives the app by role and label.
///
/// A plain `test` rather than a `testWidgets`: the property under test is that
/// the handle is *never* released, and the widget tester fails a test that
/// leaves a semantics handle active. The handle belongs to the process, so a
/// widget test would be asserting the opposite of the contract.
void main() {
  test('retains one semantics handle for the life of the process', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final before = SemanticsBinding.instance.debugOutstandingSemanticsHandles;

    // ACT: the entrypoint prepares the browser more than once in a reloaded
    // process (the app and the error page both do), so a second call must not
    // take a second handle.
    final first = retainDevSemantics();
    final second = retainDevSemantics();

    // ASSERT
    expect(
      identical(first, second),
      isTrue,
      reason: 'a second bootstrap must reuse the handle, not take another',
    );
    expect(
      SemanticsBinding.instance.debugOutstandingSemanticsHandles,
      before + 1,
      reason: 'exactly one handle is outstanding, and nothing disposes it',
    );
    expect(
      SemanticsBinding.instance.semanticsEnabled,
      isTrue,
      reason: 'the accessibility tree stays on for the whole session',
    );
  });
}
