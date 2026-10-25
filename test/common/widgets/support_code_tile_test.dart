import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/common/widgets/support_code_tile.dart';

const String supportCode = '0123AB';

void main() {
  testWidgets('shows the code and one line of explanation', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SupportCodeTile(supportCode: supportCode)),
      ),
    );

    expect(find.text(supportCode), findsOneWidget);
    expect(find.text(SupportCodeTile.title), findsOneWidget);
    expect(find.text(SupportCodeTile.explanation), findsOneWidget);
  });

  testWidgets('copies the code and confirms it', (tester) async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SupportCodeTile(supportCode: supportCode)),
      ),
    );

    await tester.tap(find.byTooltip(SupportCodeTile.copyTooltip));
    await tester.pump();

    final copy = calls.singleWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    expect((copy.arguments as Map<Object?, Object?>)['text'], supportCode);
    expect(find.text(SupportCodeTile.copiedMessage), findsOneWidget);
  });
}
