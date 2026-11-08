import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/application/create_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/update_item_use_case.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/presentation/item_form_page.dart';

class MockCreateItemUseCase extends Mock implements CreateItemUseCase {}

class MockUpdateItemUseCase extends Mock implements UpdateItemUseCase {}

void main() {
  const wishlistId = 'wishlist-1';
  const itemName = 'Desk lamp';

  late MockCreateItemUseCase createItemUseCase;
  late MockUpdateItemUseCase updateItemUseCase;

  setUpAll(() {
    registerFallbackValue(Item(name: 'fallback item'));
  });

  setUp(() {
    getIt.reset();
    createItemUseCase = MockCreateItemUseCase();
    updateItemUseCase = MockUpdateItemUseCase();
    when(
      () => createItemUseCase.execute(
        any(),
        any(),
        description: any(named: 'description'),
        url: any(named: 'url'),
        claimLimit: any(named: 'claimLimit'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => updateItemUseCase.execute(
        any(),
        any(),
        name: any(named: 'name'),
        description: any(named: 'description'),
        url: any(named: 'url'),
        claimLimit: any(named: 'claimLimit'),
      ),
    ).thenAnswer((_) async {});
    getIt.registerSingleton<CreateItemUseCase>(createItemUseCase);
    getIt.registerSingleton<UpdateItemUseCase>(updateItemUseCase);
  });

  tearDown(getIt.reset);

  /// Mounts the form on a real GoRouter stack, so saving can pop back.
  Future<void> pumpForm(WidgetTester tester, {Item? item}) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('wishlist')),
        ),
        GoRoute(
          path: '/form',
          builder: (context, state) =>
              ItemFormPage(wishlistId: wishlistId, item: item),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/form');
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

  Future<void> save(WidgetTester tester, {String label = 'Save Item'}) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
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

    await save(tester);

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

    await save(tester, label: 'Update Item');

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

    await save(tester);

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
}
