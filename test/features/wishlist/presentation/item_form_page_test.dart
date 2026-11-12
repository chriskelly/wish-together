import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/common/widgets/button_loading_indicator.dart';
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/application/create_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/reset_claims_use_case.dart';
import 'package:wishtogether/features/wishlist/application/update_item_use_case.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/presentation/item_form_page.dart';

class MockCreateItemUseCase extends Mock implements CreateItemUseCase {}

class MockUpdateItemUseCase extends Mock implements UpdateItemUseCase {}

class MockResetClaimsUseCase extends Mock implements ResetClaimsUseCase {}

class MockAuthSession extends Mock implements AuthSession {}

/// A write failure shaped like a Firestore exception: the page reads `code`
/// through the shared failure classifier.
class _WriteError implements Exception {
  _WriteError(this.code);

  final String code;
}

void main() {
  const wishlistId = 'wishlist-1';
  const itemName = 'Desk lamp';
  const saveTooltip = 'Save changes';
  const idleSaveTooltip = 'No unsaved changes';
  const resetWarning =
      "Resetting removes all claims on the item if there are any. "
      "This can't be undone.";

  late MockCreateItemUseCase createItemUseCase;
  late MockUpdateItemUseCase updateItemUseCase;
  late MockResetClaimsUseCase resetClaimsUseCase;
  late MockAuthSession authSession;

  /// Answers the create, so a test only has to state how it resolves.
  void stubCreateAnswer(Future<void> Function() answer) {
    when(
      () => createItemUseCase.execute(
        any(),
        any(),
        description: any(named: 'description'),
        url: any(named: 'url'),
        claimLimit: any(named: 'claimLimit'),
      ),
    ).thenAnswer((_) => answer());
  }

  /// Answers the update, so a test only has to state how it resolves.
  void stubUpdateAnswer(Future<void> Function() answer) {
    when(
      () => updateItemUseCase.execute(
        any(),
        any(),
        name: any(named: 'name'),
        description: any(named: 'description'),
        url: any(named: 'url'),
        claimLimit: any(named: 'claimLimit'),
      ),
    ).thenAnswer((_) => answer());
  }

  setUpAll(() {
    registerFallbackValue(Item(name: 'fallback item'));
  });

  setUp(() {
    getIt.reset();
    createItemUseCase = MockCreateItemUseCase();
    updateItemUseCase = MockUpdateItemUseCase();
    resetClaimsUseCase = MockResetClaimsUseCase();
    stubCreateAnswer(() async {});
    stubUpdateAnswer(() async {});
    when(() => resetClaimsUseCase.execute(any(), any()))
        .thenAnswer((_) async {});
    getIt.registerSingleton<CreateItemUseCase>(createItemUseCase);
    getIt.registerSingleton<UpdateItemUseCase>(updateItemUseCase);
    getIt.registerSingleton<ResetClaimsUseCase>(resetClaimsUseCase);
    authSession = MockAuthSession();
    when(() => authSession.currentUserId).thenReturn('owner-uid');
    getIt.registerSingleton<AuthSession>(authSession);
  });

  tearDown(getIt.reset);

  /// Mounts the form on a real GoRouter stack, so saving can pop back, and
  /// wires the edit route's `onExit` guard exactly as the app router does.
  Future<GoRouter> pumpForm(WidgetTester tester, {Item? item}) async {
    final args = item == null ? null : EditItemRouteArgs(item);
    final router = GoRouter(
      initialLocation: '/',
      redirect: (context, state) =>
          authSession.currentUserId == null && state.uri.path != '/login'
          ? '/login'
          : null,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('wishlist')),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const Scaffold(body: Text('login')),
        ),
        // Take the real edit route's onExit, so a change there cannot leave
        // this suite green while browser back stops asking.
        GoRoute(
          path: '/form',
          onExit: itemFormPageEditRoute().onExit,
          builder: (context, state) => ItemFormPage(
            wishlistId: wishlistId,
            item: args?.item,
            leaveGuard: args?.leaveGuard,
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/form', extra: args);
    await tester.pumpAndSettle();
    return router;
  }

  /// The browser's back button as the web engine reports it: a navigation
  /// message, not a Navigator pop.
  Future<void> browserBack(WidgetTester tester) async {
    final message = SystemChannels.navigation.codec.encodeMethodCall(
      const MethodCall('pushRouteInformation', <String, Object?>{
        'location': '/',
        'state': null,
      }),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.navigation.name,
      message,
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  Map<String, DateTime> claimsBy(int people) => {
    for (var index = 0; index < people; index++)
      'reader-$index': DateTime.utc(2026, 1, 1),
  };

  Finder stepperIcon(IconData icon) => find.widgetWithIcon(IconButton, icon);

  IconButton stepperButton(WidgetTester tester, IconData icon) =>
      tester.widget<IconButton>(stepperIcon(icon));

  SwitchListTile switchTile(WidgetTester tester) =>
      tester.widget<SwitchListTile>(find.byType(SwitchListTile));

  bool minusEnabled(WidgetTester tester) =>
      stepperButton(tester, Icons.remove).onPressed != null;

  bool plusEnabled(WidgetTester tester) =>
      stepperButton(tester, Icons.add).onPressed != null;

  bool unlimitedSwitchEnabled(WidgetTester tester) =>
      switchTile(tester).onChanged != null;

  Future<void> tapMinus(WidgetTester tester) async {
    await tester.tap(stepperIcon(Icons.remove));
    await tester.pump();
  }

  Future<void> tapPlus(WidgetTester tester) async {
    await tester.tap(stepperIcon(Icons.add));
    await tester.pump();
  }

  Future<void> tapUnlimited(WidgetTester tester) async {
    await tester.tap(find.text('Unlimited'));
    await tester.pump();
  }

  /// Taps the create form's explicit `Save Item` button.
  Future<void> tapCreate(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save Item'));
    await tester.tap(find.text('Save Item'));
    await tester.pumpAndSettle();
  }

  /// The item update as the page makes it, for assertions that no write
  /// happened.
  void verifyUpdateNever() => verifyNever(
    () => updateItemUseCase.execute(
      any(),
      any(),
      name: any(named: 'name'),
      description: any(named: 'description'),
      url: any(named: 'url'),
      claimLimit: any(named: 'claimLimit'),
    ),
  );

  Finder saveAction() => find.byTooltip(saveTooltip);

  Finder idleSaveAction() => find.byTooltip(idleSaveTooltip);

  IconButton saveButton(WidgetTester tester, {String tooltip = saveTooltip}) =>
      tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );

  bool saveEnabled(WidgetTester tester) => saveButton(tester).onPressed != null;

  TextField nameField(WidgetTester tester) => tester.widget<TextField>(
    find.descendant(
      of: find.byType(TextFormField).first,
      matching: find.byType(TextField),
    ),
  );

  Future<void> editName(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextFormField).first, value);
    await tester.pump();
  }

  /// Taps the edit form's app-bar check mark.
  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(saveAction());
    await tester.pumpAndSettle();
  }

  Future<void> leave(WidgetTester tester) async {
    await tester.pageBack();
    await tester.pumpAndSettle();
  }

  Finder resetButton() => find.widgetWithText(OutlinedButton, 'Reset claims');

  Future<void> openResetDialog(WidgetTester tester) async {
    await tester.ensureVisible(resetButton());
    await tester.tap(resetButton());
    await tester.pumpAndSettle();
  }

  Future<void> confirmReset(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, 'Reset claims'));
    await tester.pumpAndSettle();
  }

  testWidgets('starts a new item at one claim and cannot go lower', (
    tester,
  ) async {
    await pumpForm(tester);

    expect(find.text('1'), findsOneWidget);
    expect(minusEnabled(tester), isFalse);
    expect(plusEnabled(tester), isTrue);
    expect(unlimitedSwitchEnabled(tester), isTrue);
  });

  testWidgets('announces the claim limit once', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpForm(tester);

    expect(find.semantics.byLabel('Claim limit: 1'), findsOne);
    expect(find.semantics.byLabel('Claim limit: 1\n1'), findsNothing);
    semantics.dispose();
  });

  testWidgets('announces unlimited without repeating the value', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claimLimit: 0),
    );

    expect(find.semantics.byLabel('No claim limit'), findsOne);
    expect(find.semantics.byLabel('No claim limit\n∞'), findsNothing);
    semantics.dispose();
  });

  testWidgets('increments the limit with +', (tester) async {
    await pumpForm(tester);

    await tapPlus(tester);

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('stops the stepper at 99', (tester) async {
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claimLimit: 99),
    );

    expect(find.text('99'), findsOneWidget);
    expect(plusEnabled(tester), isFalse);
    expect(minusEnabled(tester), isTrue);
  });

  testWidgets('keeps a stored limit above the stepper ceiling', (tester) async {
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claimLimit: 150),
    );

    expect(find.text('150'), findsOneWidget);
    expect(plusEnabled(tester), isFalse);
    expect(minusEnabled(tester), isFalse);
  });

  testWidgets('fits a preserved four-digit limit on a narrow phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claimLimit: 1200),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('1200'), findsOneWidget);
  });

  testWidgets('starts an edit at the claim count and cannot go below it', (
    tester,
  ) async {
    await pumpForm(
      tester,
      item: Item(
        id: 'item-1',
        name: itemName,
        claimLimit: 5,
        claims: claimsBy(3),
      ),
    );

    await tapMinus(tester);
    await tapMinus(tester);

    expect(find.text('3'), findsOneWidget);
    expect(minusEnabled(tester), isFalse);
  });

  testWidgets('starts an edit with no claims at one', (tester) async {
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claimLimit: 5),
    );

    for (var index = 0; index < 4; index++) {
      await tapMinus(tester);
    }

    expect(find.text('1'), findsOneWidget);
    expect(minusEnabled(tester), isFalse);
  });

  testWidgets('allows an edit at the current claim count but not below', (
    tester,
  ) async {
    await pumpForm(
      tester,
      item: Item(
        id: 'item-1',
        name: itemName,
        claimLimit: 3,
        claims: claimsBy(3),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(minusEnabled(tester), isFalse);
    expect(plusEnabled(tester), isTrue);
  });

  testWidgets('starts at the claim count when the stored limit is lower', (
    tester,
  ) async {
    await pumpForm(
      tester,
      item: Item(
        id: 'item-1',
        name: itemName,
        claimLimit: 1,
        claims: claimsBy(3),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(minusEnabled(tester), isFalse);
  });

  testWidgets('switching Unlimited on shows ∞ and disables the stepper', (
    tester,
  ) async {
    await pumpForm(tester);

    await tapUnlimited(tester);

    expect(find.text('∞'), findsOneWidget);
    expect(unlimitedSwitchEnabled(tester), isTrue);
    expect(switchTile(tester).value, isTrue);
    expect(minusEnabled(tester), isFalse);
  });

  testWidgets('switching Unlimited off restores the minimum', (tester) async {
    await pumpForm(
      tester,
      item: Item(
        id: 'item-1',
        name: itemName,
        claimLimit: 5,
        claims: claimsBy(3),
      ),
    );

    await tapUnlimited(tester);
    await tapUnlimited(tester);

    expect(find.text('3'), findsOneWidget);
    expect(switchTile(tester).value, isFalse);
  });

  testWidgets('+ from ∞ sets the minimum and turns the switch off', (
    tester,
  ) async {
    await pumpForm(
      tester,
      item: Item(
        id: 'item-1',
        name: itemName,
        claimLimit: 5,
        claims: claimsBy(3),
      ),
    );

    await tapUnlimited(tester);
    await tapPlus(tester);

    expect(find.text('3'), findsOneWidget);
    expect(switchTile(tester).value, isFalse);
  });

  testWidgets('starts an unlimited item at ∞', (tester) async {
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claimLimit: 0),
    );

    expect(find.text('∞'), findsOneWidget);
    expect(switchTile(tester).value, isTrue);
  });

  testWidgets('keeps an item with over 99 claims unlimited', (tester) async {
    await pumpForm(
      tester,
      item: Item(
        id: 'item-1',
        name: itemName,
        claimLimit: 0,
        claims: claimsBy(100),
      ),
    );

    expect(find.text('∞'), findsOneWidget);
    expect(unlimitedSwitchEnabled(tester), isFalse);
    expect(plusEnabled(tester), isFalse);
    expect(minusEnabled(tester), isFalse);
  });

  testWidgets('saves the chosen limit when creating', (tester) async {
    await pumpForm(tester);
    await tester.enterText(find.byType(TextFormField).first, itemName);
    await tapPlus(tester);
    await tapPlus(tester);

    await tapCreate(tester);

    verify(
      () => createItemUseCase.execute(
        wishlistId,
        itemName,
        description: null,
        url: null,
        claimLimit: 3,
      ),
    ).called(1);
  });

  testWidgets('saves the chosen limit when updating', (tester) async {
    final item = Item(id: 'item-1', name: itemName, claimLimit: 1);
    await pumpForm(tester, item: item);
    await tapPlus(tester);
    await tapPlus(tester);

    await tapSave(tester);

    verify(
      () => updateItemUseCase.execute(
        wishlistId,
        item,
        name: itemName,
        description: null,
        url: null,
        claimLimit: 3,
      ),
    ).called(1);
  });

  testWidgets('saves unlimited as zero', (tester) async {
    await pumpForm(tester);
    await tester.enterText(find.byType(TextFormField).first, itemName);
    await tapUnlimited(tester);

    await tapCreate(tester);

    verify(
      () => createItemUseCase.execute(
        wishlistId,
        itemName,
        description: null,
        url: null,
        claimLimit: 0,
      ),
    ).called(1);
  });

  testWidgets('hides reset claims while creating an item', (tester) async {
    await pumpForm(tester);

    expect(find.text('Reset claims'), findsNothing);
  });

  testWidgets('offers reset claims on an edit even with no claims', (
    tester,
  ) async {
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName),
    );

    expect(resetButton(), findsOneWidget);
    expect(find.text(resetWarning), findsOneWidget);
  });

  testWidgets('offers reset claims on an edit with claims', (tester) async {
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claims: claimsBy(2)),
    );

    expect(resetButton(), findsOneWidget);
  });

  testWidgets('cancelling the reset leaves the claims untouched', (
    tester,
  ) async {
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claims: claimsBy(2)),
    );

    await openResetDialog(tester);
    expect(find.text('Reset claims?'), findsOneWidget);
    expect(find.text(resetWarning), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => resetClaimsUseCase.execute(any(), any()));
  });

  testWidgets('confirming the reset clears claims and stays on the form', (
    tester,
  ) async {
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claims: claimsBy(2)),
    );

    await openResetDialog(tester);
    await confirmReset(tester);

    verify(() => resetClaimsUseCase.execute(wishlistId, 'item-1')).called(1);
    expect(find.text('Claims reset.'), findsOneWidget);
    expect(find.text('wishlist'), findsNothing);
    expect(find.text('Edit Item'), findsOneWidget);
  });

  testWidgets('shows the fallback copy when a reset fails', (tester) async {
    when(() => resetClaimsUseCase.execute(wishlistId, 'item-1'))
        .thenThrow(Exception('server says no'));
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claims: claimsBy(1)),
    );

    await openResetDialog(tester);
    await confirmReset(tester);

    expect(
      find.text("Couldn't reset claims. Please try again."),
      findsOneWidget,
    );
    expect(find.textContaining('server says no'), findsNothing);
  });

  testWidgets('shows the signed-out copy when a reset is refused', (
    tester,
  ) async {
    when(() => resetClaimsUseCase.execute(wishlistId, 'item-1'))
        .thenThrow(const ClaimFailure(ClaimFailureReason.signedOut));
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claims: claimsBy(1)),
    );

    await openResetDialog(tester);
    await confirmReset(tester);

    expect(find.text('Please sign in again to reset claims.'), findsOneWidget);
  });

  testWidgets('shows the offline copy when a reset cannot reach the server', (
    tester,
  ) async {
    when(() => resetClaimsUseCase.execute(wishlistId, 'item-1'))
        .thenThrow(const ClaimFailure(ClaimFailureReason.offline));
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claims: claimsBy(1)),
    );

    await openResetDialog(tester);
    await confirmReset(tester);

    expect(
      find.text(
        "Couldn't reach the server. Check your connection and try again.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows the denied copy when the owner is no longer allowed', (
    tester,
  ) async {
    when(() => resetClaimsUseCase.execute(wishlistId, 'item-1'))
        .thenThrow(const ClaimFailure(ClaimFailureReason.accessDenied));
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claims: claimsBy(1)),
    );

    await openResetDialog(tester);
    await confirmReset(tester);

    expect(
      find.text("You don't have permission to reset this item's claims."),
      findsOneWidget,
    );
  });

  testWidgets('keeps save usable while a reset is pending', (tester) async {
    final pending = Completer<void>();
    when(() => resetClaimsUseCase.execute(wishlistId, 'item-1'))
        .thenAnswer((_) => pending.future);
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claims: claimsBy(1)),
    );
    await editName(tester, '$itemName edited');

    await openResetDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Reset claims'));
    await tester.pump();
    await tester.pump();

    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
    expect(find.byType(ButtonLoadingIndicator), findsOneWidget);
    expect(saveEnabled(tester), isTrue);

    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('does not pop twice when save and reset finish together', (
    tester,
  ) async {
    final resetPending = Completer<void>();
    final savePending = Completer<void>();
    when(() => resetClaimsUseCase.execute(wishlistId, 'item-1'))
        .thenAnswer((_) => resetPending.future);
    stubUpdateAnswer(() => savePending.future);
    await pumpForm(
      tester,
      item: Item(id: 'item-1', name: itemName, claims: claimsBy(1)),
    );
    await editName(tester, '$itemName edited');

    await openResetDialog(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Reset claims'));
    await tester.pump();
    await tester.pump();
    await tester.tap(saveAction());
    await tester.pump();

    verify(
      () => updateItemUseCase.execute(
        any(),
        any(),
        name: any(named: 'name'),
        description: any(named: 'description'),
        url: any(named: 'url'),
        claimLimit: any(named: 'claimLimit'),
      ),
    ).called(1);

    resetPending.complete();
    await tester.pump();
    savePending.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('wishlist'), findsOneWidget);
  });

  group('edit save and leave', () {
    const editedName = 'Desk lamp, taller';
    const editedDescription = 'A warm reading light';
    const editedUrl = 'https://example.com/lamp';

    Item lamp({String name = itemName, int claimLimit = 1, int claims = 0}) =>
        Item(
          id: 'item-1',
          name: name,
          claimLimit: claimLimit,
          claims: claimsBy(claims),
        );

    testWidgets('does not open the keyboard on an edit', (tester) async {
      await pumpForm(tester, item: lamp());

      expect(nameField(tester).autofocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('opens the keyboard on create', (tester) async {
      await pumpForm(tester);

      expect(nameField(tester).autofocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('disables save until the form differs from the item', (
      tester,
    ) async {
      await pumpForm(tester, item: lamp());

      expect(saveButton(tester, tooltip: idleSaveTooltip).onPressed, isNull);

      await editName(tester, editedName);

      expect(saveEnabled(tester), isTrue);
      expect(saveAction(), findsOneWidget);
    });

    testWidgets('leaves immediately when nothing changed', (tester) async {
      await pumpForm(tester, item: lamp());

      await leave(tester);

      expect(find.text('wishlist'), findsOneWidget);
      expect(find.text('Save your changes?'), findsNothing);
    });

    testWidgets('asks before leaving an unsaved edit', (tester) async {
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);

      await leave(tester);

      expect(find.text('Save your changes?'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Keep editing'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Discard'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Save'), findsOneWidget);
      expect(find.text('wishlist'), findsNothing);
    });

    testWidgets('asks before the browser back replaces the form', (
      tester,
    ) async {
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);

      await browserBack(tester);

      expect(find.text('Save your changes?'), findsOneWidget);
      expect(find.text('wishlist'), findsNothing);
      verifyUpdateNever();
    });

    testWidgets('keeps the page when the browser back prompt is cancelled', (
      tester,
    ) async {
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);
      await browserBack(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Keep editing'));
      await tester.pumpAndSettle();

      expect(find.text('wishlist'), findsNothing);
      expect(nameField(tester).controller!.text, editedName);
    });

    testWidgets('discarding from the browser back leaves without writing', (
      tester,
    ) async {
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);
      await browserBack(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(find.text('wishlist'), findsOneWidget);
      verifyUpdateNever();
    });

    testWidgets('saving from the browser back writes and leaves', (
      tester,
    ) async {
      final item = lamp();
      await pumpForm(tester, item: item);
      await editName(tester, editedName);
      await browserBack(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('wishlist'), findsOneWidget);
      verify(
        () => updateItemUseCase.execute(
          wishlistId,
          item,
          name: editedName,
          description: null,
          url: null,
          claimLimit: 1,
        ),
      ).called(1);
    });

    testWidgets('does not stack the leave dialog on a double browser back', (
      tester,
    ) async {
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);

      await browserBack(tester);
      await browserBack(tester);

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Keep editing'));
      await tester.pumpAndSettle();
      await browserBack(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('stays on the form when the browser back save fails', (
      tester,
    ) async {
      stubUpdateAnswer(() async => throw _WriteError('unavailable'));
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);
      await browserBack(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Couldn't reach the server. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(find.text('wishlist'), findsNothing);
    });

    testWidgets('lets a clean form leave on browser back', (tester) async {
      await pumpForm(tester, item: lamp());

      await browserBack(tester);

      expect(find.text('wishlist'), findsOneWidget);
      expect(find.text('Save your changes?'), findsNothing);
    });

    testWidgets('keep editing returns to the unsaved form', (tester) async {
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);
      await leave(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Keep editing'));
      await tester.pumpAndSettle();

      expect(find.text('wishlist'), findsNothing);
      expect(nameField(tester).controller!.text, editedName);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('discard leaves without writing', (tester) async {
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);
      await leave(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(find.text('wishlist'), findsOneWidget);
      verifyUpdateNever();
    });

    testWidgets('save in the leave dialog writes and leaves', (tester) async {
      final item = lamp();
      await pumpForm(tester, item: item);
      await editName(tester, editedName);
      await leave(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('wishlist'), findsOneWidget);
      verify(
        () => updateItemUseCase.execute(
          wishlistId,
          item,
          name: editedName,
          description: null,
          url: null,
          claimLimit: 1,
        ),
      ).called(1);
    });

    testWidgets('does not leave when the dialog save is invalid', (
      tester,
    ) async {
      await pumpForm(tester, item: lamp());
      await editName(tester, '');
      await leave(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a name for the item.'), findsOneWidget);
      expect(find.text('wishlist'), findsNothing);
      verifyUpdateNever();
    });

    testWidgets('saves a rapid edit sequence once with the final values', (
      tester,
    ) async {
      final item = lamp();
      await pumpForm(tester, item: item);
      await tester.enterText(find.byType(TextFormField).at(0), 'a');
      await tester.enterText(find.byType(TextFormField).at(1), 'b');
      await tester.enterText(find.byType(TextFormField).at(2), 'c');
      await tester.enterText(find.byType(TextFormField).at(0), editedName);
      await tester.enterText(
        find.byType(TextFormField).at(1),
        editedDescription,
      );
      await tester.enterText(find.byType(TextFormField).at(2), editedUrl);
      await tester.pump();

      await tapSave(tester);

      verify(
        () => updateItemUseCase.execute(
          wishlistId,
          item,
          name: editedName,
          description: editedDescription,
          url: editedUrl,
          claimLimit: 1,
        ),
      ).called(1);
      expect(find.text('wishlist'), findsOneWidget);
    });

    testWidgets('keeps a failed save visible and retries from the check mark', (
      tester,
    ) async {
      var calls = 0;
      stubUpdateAnswer(() async {
        calls++;
        if (calls == 1) {
          throw _WriteError('unavailable');
        }
      });
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);

      await tapSave(tester);

      expect(
        find.text(
          "Couldn't reach the server. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(find.text('wishlist'), findsNothing);
      expect(nameField(tester).controller!.text, editedName);
      expect(saveEnabled(tester), isTrue);

      await tapSave(tester);

      expect(find.text('wishlist'), findsOneWidget);
      expect(calls, 2);
    });

    testWidgets('keeps the failure banner when focus moves without typing', (
      tester,
    ) async {
      stubUpdateAnswer(() async => throw _WriteError('unavailable'));
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);
      await tapSave(tester);
      const banner =
          "Couldn't reach the server. Check your connection and try again.";
      expect(find.text(banner), findsOneWidget);

      await tester.tap(find.byType(TextFormField).at(1));
      await tester.pump();

      expect(find.text(banner), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    });

    testWidgets('clears the failure banner when text changes', (tester) async {
      stubUpdateAnswer(() async => throw _WriteError('unavailable'));
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);
      await tapSave(tester);
      const banner =
          "Couldn't reach the server. Check your connection and try again.";
      expect(find.text(banner), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(1), 'A note');
      await tester.pump();

      expect(find.text(banner), findsNothing);
    });

    testWidgets('clears the failure banner when the claim limit changes', (
      tester,
    ) async {
      stubUpdateAnswer(() async => throw _WriteError('unavailable'));
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);
      await tapSave(tester);
      expect(
        find.text(
          "Couldn't reach the server. Check your connection and try again.",
        ),
        findsOneWidget,
      );

      await tapPlus(tester);

      expect(
        find.text(
          "Couldn't reach the server. Check your connection and try again.",
        ),
        findsNothing,
      );
    });

    testWidgets('does not leak the exception text on an unexpected failure', (
      tester,
    ) async {
      stubUpdateAnswer(() async {
        throw Exception('server says no');
      });
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);

      await tapSave(tester);

      expect(
        find.text("Couldn't save your changes. Please try again."),
        findsOneWidget,
      );
      expect(find.textContaining('server says no'), findsNothing);
      expect(find.text('wishlist'), findsNothing);
    });

    testWidgets('stops waiting on a write that never confirms', (tester) async {
      final pending = Completer<void>();
      stubUpdateAnswer(() => pending.future);
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);

      await tester.tap(saveAction());
      await tester.pump();
      expect(find.byType(ButtonLoadingIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();

      expect(
        find.text(
          "Couldn't confirm the save. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(find.text('wishlist'), findsNothing);

      pending.complete();
      await tester.pumpAndSettle();

      expect(find.text('wishlist'), findsNothing);
      expect(
        find.text(
          "Couldn't confirm the save. Check your connection and try again.",
        ),
        findsNothing,
      );
      expect(idleSaveAction(), findsOneWidget);
    });

    testWidgets('keeps edits typed while a save is in flight', (tester) async {
      final pending = Completer<void>();
      stubUpdateAnswer(() => pending.future);
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);

      await tester.tap(saveAction());
      await tester.pump();
      await editName(tester, '$editedName again');
      pending.complete();
      await tester.pumpAndSettle();

      expect(find.text('wishlist'), findsNothing);
      expect(nameField(tester).controller!.text, '$editedName again');
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('does not leave while a save is in flight', (tester) async {
      final pending = Completer<void>();
      stubUpdateAnswer(() => pending.future);
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);

      await tester.tap(saveAction());
      await tester.pump();
      await tester.pageBack();
      await tester.pump();

      expect(find.text('Saving your changes…'), findsOneWidget);
      expect(find.text('wishlist'), findsNothing);

      pending.complete();
      await tester.pumpAndSettle();

      expect(find.text('wishlist'), findsOneWidget);
    });

    testWidgets('resets claims without closing the form or dropping typing', (
      tester,
    ) async {
      await pumpForm(tester, item: lamp(claims: 2));
      await editName(tester, editedName);

      await openResetDialog(tester);
      await confirmReset(tester);

      expect(find.text('Claims reset.'), findsOneWidget);
      expect(find.text('wishlist'), findsNothing);
      expect(nameField(tester).controller!.text, editedName);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('lowers the stepper minimum after a reset', (tester) async {
      await pumpForm(tester, item: lamp(claimLimit: 5, claims: 3));

      await openResetDialog(tester);
      await confirmReset(tester);
      await tester.ensureVisible(stepperIcon(Icons.remove));
      await tester.pump();

      for (var index = 0; index < 4; index++) {
        await tapMinus(tester);
      }

      expect(find.text('1'), findsOneWidget);
      expect(minusEnabled(tester), isFalse);
    });

    testWidgets('re-enables the unlimited switch after a reset', (
      tester,
    ) async {
      await pumpForm(tester, item: lamp(claimLimit: 0, claims: 100));
      expect(unlimitedSwitchEnabled(tester), isFalse);

      await openResetDialog(tester);
      await confirmReset(tester);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.pump();

      expect(unlimitedSwitchEnabled(tester), isTrue);
    });

    testWidgets('shows classified copy when creating fails', (tester) async {
      stubCreateAnswer(() async => throw _WriteError('permission-denied'));
      await pumpForm(tester);
      await tester.enterText(find.byType(TextFormField).first, itemName);
      await tester.pump();

      await tapCreate(tester);

      expect(
        find.text("You don't have permission to save this item."),
        findsOneWidget,
      );
      expect(find.text('wishlist'), findsNothing);
    });

    testWidgets('never lets a slow create invite a second add', (tester) async {
      final pending = Completer<void>();
      stubCreateAnswer(() => pending.future);
      await pumpForm(tester);
      await tester.enterText(find.byType(TextFormField).first, itemName);
      await tester.pump();

      await tester.tap(find.text('Save Item'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));

      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
      expect(
        find.text(
          "Couldn't confirm the save. Check your connection and try again.",
        ),
        findsNothing,
      );
      verify(
        () => createItemUseCase.execute(
          wishlistId,
          itemName,
          description: any(named: 'description'),
          url: any(named: 'url'),
          claimLimit: any(named: 'claimLimit'),
        ),
      ).called(1);

      pending.complete();
      await tester.pumpAndSettle();

      expect(find.text('wishlist'), findsOneWidget);
    });

    testWidgets('lets an account change replace the dirty form', (
      tester,
    ) async {
      await pumpForm(tester, item: lamp());
      await editName(tester, editedName);
      when(() => authSession.currentUserId).thenReturn('other-uid');

      await browserBack(tester);

      expect(find.text('Save your changes?'), findsNothing);
      expect(find.text('wishlist'), findsOneWidget);
    });

    testWidgets('lets a sign-out redirect replace the dirty form', (
      tester,
    ) async {
      final router = await pumpForm(tester, item: lamp());
      await editName(tester, editedName);
      when(() => authSession.currentUserId).thenReturn(null);

      router.refresh();
      await tester.pumpAndSettle();

      expect(find.text('Save your changes?'), findsNothing);
      expect(find.text('login'), findsOneWidget);
      expect(find.text('wishlist'), findsNothing);
    });

    testWidgets('keeps the create form on its explicit save button', (
      tester,
    ) async {
      await pumpForm(tester);

      expect(saveAction(), findsNothing);
      expect(idleSaveAction(), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Save Item'), findsOneWidget);
    });
  });
}
