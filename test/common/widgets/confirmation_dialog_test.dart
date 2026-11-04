import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/core/theme.dart';

const openLabel = 'Open dialog';
const confirmLabel = 'Delete';
const explicitColour = Color(0xFF00FF00);

void main() {
  testWidgets('the confirm action defaults to the error role', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: const Scaffold(body: _DialogHost()),
      ),
    );

    await tester.tap(find.text(openLabel));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text(confirmLabel)).style!.color,
      lightTheme.colorScheme.error,
    );
  });

  testWidgets('an explicit confirm colour still wins', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: const Scaffold(body: _DialogHost(confirmColor: explicitColour)),
      ),
    );

    await tester.tap(find.text(openLabel));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.text(confirmLabel)).style!.color,
      explicitColour,
    );
  });
}

class _DialogHost extends StatelessWidget {
  final Color? confirmColor;

  const _DialogHost({this.confirmColor});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => showConfirmationDialog(
        context: context,
        title: 'Confirm Deletion',
        content: 'Are you sure?',
        confirmText: confirmLabel,
        confirmColor: confirmColor,
      ),
      child: const Text(openLabel),
    );
  }
}
