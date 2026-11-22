import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/keyboard_dismissal.dart';

import '../support/focus_node.dart';

/// A page with a field and enough neutral space to start a swipe anywhere.
///
/// The wrapper sits in `MaterialApp.builder`, as it does in production, so the
/// harness also covers routes and dialogs above the home page. The field opts
/// out of Flutter's own mouse-tap-outside unfocus, so the tests can attribute a
/// dismissal to [KeyboardDismissal] alone.
Widget page() => MaterialApp(
  builder: (context, child) => KeyboardDismissal(child: child!),
  home: Scaffold(
    body: Column(
      children: [
        const SizedBox(height: 120),
        const Text('neutral'),
        const TextButton(onPressed: _noop, child: Text('control')),
        TextField(onTapOutside: _ignorePointerDown),
        const _DialogOpener(),
      ],
    ),
  ),
);

/// A long page, so a dismissing swipe also has somewhere to scroll.
Widget scrollablePage(ScrollController controller) => MaterialApp(
  builder: (context, child) => KeyboardDismissal(child: child!),
  home: Scaffold(
    body: SingleChildScrollView(
      controller: controller,
      child: const Column(
        children: [
          SizedBox(height: 120),
          Text('neutral'),
          TextField(),
          SizedBox(height: 1200),
        ],
      ),
    ),
  ),
);

class _DialogOpener extends StatelessWidget {
  const _DialogOpener();

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(),
              SizedBox(height: 120),
              Text('dialog neutral'),
            ],
          ),
        ),
      ),
      child: const Text('open dialog'),
    );
  }
}

void _noop() {}

void _ignorePointerDown(PointerDownEvent event) {}

/// Pumps the page and focuses its field without reporting a keyboard inset.
Future<void> pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(page());
  await tester.showKeyboard(find.byType(TextField));
  await tester.pump();
}

/// Pumps the page with the platform's on-screen keyboard inset set.
Future<void> pumpPageWithKeyboardUp(WidgetTester tester) async {
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  addTearDown(tester.view.resetViewInsets);
  await pumpPage(tester);
}

void main() {
  testWidgets('a deliberate downward swipe dismisses the keyboard', (
    tester,
  ) async {
    // Arrange
    await pumpPageWithKeyboardUp(tester);
    expect(focusNodeOf(tester, find.byType(TextField)).hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    // Act
    await tester.drag(find.text('neutral'), const Offset(0, 120));
    await tester.pump();

    // Assert
    expect(focusNodeOf(tester, find.byType(TextField)).hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('a tap does not dismiss the keyboard', (tester) async {
    // Arrange
    await pumpPageWithKeyboardUp(tester);

    // Act
    await tester.tap(find.text('neutral'));
    await tester.pump();

    // Assert
    expect(focusNodeOf(tester, find.byType(TextField)).hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
  });

  testWidgets('an upward drag does not dismiss the keyboard', (tester) async {
    // Arrange
    await pumpPageWithKeyboardUp(tester);

    // Act
    await tester.drag(find.text('neutral'), const Offset(0, -120));
    await tester.pump();

    // Assert
    expect(focusNodeOf(tester, find.byType(TextField)).hasFocus, isTrue);
  });

  testWidgets('a horizontal drag does not dismiss the keyboard', (
    tester,
  ) async {
    // Arrange
    await pumpPageWithKeyboardUp(tester);

    // Act
    await tester.drag(find.text('neutral'), const Offset(120, 0));
    await tester.pump();

    // Assert
    expect(focusNodeOf(tester, find.byType(TextField)).hasFocus, isTrue);
  });

  testWidgets('a mouse drag does not dismiss the keyboard', (tester) async {
    // Arrange
    await pumpPageWithKeyboardUp(tester);

    // Act
    await tester.drag(
      find.text('neutral'),
      const Offset(0, 120),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    // Assert
    expect(focusNodeOf(tester, find.byType(TextField)).hasFocus, isTrue);
  });

  testWidgets('a downward swipe with no keyboard does nothing', (tester) async {
    // Arrange: the platform reports no keyboard inset.
    await pumpPage(tester);

    // Act
    await tester.drag(find.text('neutral'), const Offset(0, 120));
    await tester.pump();

    // Assert
    expect(focusNodeOf(tester, find.byType(TextField)).hasFocus, isTrue);
  });

  testWidgets('the gesture arms when the keyboard inset appears later', (
    tester,
  ) async {
    // Arrange: production mounts the app before the keyboard reports its
    // inset, so the gate has to update from the dependency lifecycle.
    await pumpPage(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();

    // Act
    await tester.drag(find.text('neutral'), const Offset(0, 120));
    await tester.pump();

    // Assert
    expect(focusNodeOf(tester, find.byType(TextField)).hasFocus, isFalse);
  });

  testWidgets('a drag that starts on a control still dismisses', (
    tester,
  ) async {
    // Arrange
    await pumpPageWithKeyboardUp(tester);

    // Act
    await tester.drag(find.text('control'), const Offset(0, 120));
    await tester.pump();

    // Assert
    expect(focusNodeOf(tester, find.byType(TextField)).hasFocus, isFalse);
  });

  testWidgets('a downward swipe dismisses a dialog field', (tester) async {
    // Arrange: the dialog lives above the home route, inside the builder's
    // wrapper, which is where production puts it too.
    await pumpPageWithKeyboardUp(tester);
    await tester.tap(find.text('open dialog'));
    await tester.pumpAndSettle();
    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.showKeyboard(dialogField);
    await tester.pump();
    expect(focusNodeOf(tester, dialogField).hasFocus, isTrue);

    // Act
    await tester.drag(find.text('dialog neutral'), const Offset(0, 120));
    await tester.pump();

    // Assert
    expect(focusNodeOf(tester, dialogField).hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });

  testWidgets('a downward swipe still scrolls while dismissing', (
    tester,
  ) async {
    // Arrange
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(scrollablePage(controller));
    await tester.showKeyboard(find.byType(TextField));
    await tester.pump();
    final focusNode = focusNodeOf(tester, find.byType(TextField));
    await tester.drag(find.text('neutral'), const Offset(0, -200));
    await tester.pump();
    final offsetBeforeSwipe = controller.offset;
    expect(offsetBeforeSwipe, greaterThan(0));
    expect(focusNode.hasFocus, isTrue);

    // Act: swipe down on the page content below the field.
    await tester.dragFrom(const Offset(400, 250), const Offset(0, 50));
    await tester.pump();

    // Assert
    expect(controller.offset, lessThan(offsetBeforeSwipe));
    expect(focusNode.hasFocus, isFalse);
  });
}
