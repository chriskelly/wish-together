import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/application/create_wishlist_use_case.dart';
import 'package:wishtogether/features/wishlist/application/update_wishlist_use_case.dart';
import 'package:wishtogether/features/wishlist/presentation/wishlist_form_page.dart';
import 'package:wishtogether/main.dart';

import '../../../support/focus_node.dart';

class MockCreateWishlistUseCase extends Mock implements CreateWishlistUseCase {}

class MockUpdateWishlistUseCase extends Mock implements UpdateWishlistUseCase {}

void main() {
  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<CreateWishlistUseCase>(MockCreateWishlistUseCase());
    getIt.registerSingleton<UpdateWishlistUseCase>(MockUpdateWishlistUseCase());
  });

  tearDown(getIt.reset);

  testWidgets('a downward swipe drops focus and hides the keyboard', (
    tester,
  ) async {
    // Arrange: the name field has the keyboard up on a form too short to
    // scroll, so the gesture has to work on the page itself.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    final router = GoRouter(
      initialLocation: WishlistFormPage.createRoute,
      routes: <RouteBase>[wishlistFormPageRoute()],
    );
    await tester.pumpWidget(WishTogetherApp(router: router));
    await tester.pump();
    await tester.showKeyboard(find.byType(TextFormField));
    await tester.pump();
    final focusNode = focusNodeOf(tester, find.byType(TextFormField));
    expect(focusNode.hasFocus, isTrue);

    // Act: start on the blank body below the form, not the app bar. This
    // short form has nothing to scroll, so the page's empty area is the
    // gesture surface the ticket needs to cover.
    final start =
        tester.getBottomLeft(find.byType(ElevatedButton)) + const Offset(0, 30);
    await tester.dragFrom(start, const Offset(0, 50));
    await tester.pump();

    // Assert
    expect(focusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
