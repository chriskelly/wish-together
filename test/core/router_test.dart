import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/auth/presentation/login_page.dart';
import 'package:wishtogether/features/auth/presentation/profile_page.dart';
import 'package:wishtogether/features/auth/presentation/verification_page.dart';
import 'package:wishtogether/features/group/presentation/group_details_page.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUserRepository extends Mock implements UserRepository {}

void main() {
  late MockAuthService mockAuthService;
  late MockUserRepository mockUserRepository;

  setUp(() {
    mockAuthService = MockAuthService();
    mockUserRepository = MockUserRepository();
  });

  group('handleRedirect', () {
    group('user not logged in', () {
      setUp(() {
        when(() => mockAuthService.currentUserId).thenReturn(null);
      });

      test('should not redirect when on the login page', () async {
        final result = await handleRedirect(
          LoginPage.route,
          mockAuthService,
          userRepo: mockUserRepository,
        );
        expect(result, isNull);
      });

      test('should not redirect when on the verify page', () async {
        final result = await handleRedirect(
          VerificationPage.route,
          mockAuthService,
          userRepo: mockUserRepository,
        );
        expect(result, isNull);
      });

      test('should redirect to login page from a protected page with redirect', () async {
        const initialRoute = HomePage.route; // This is '/'
        final result = await handleRedirect(
          initialRoute,
          mockAuthService,
          userRepo: mockUserRepository,
        );
        final expectedRedirect =
            '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(initialRoute)}';
        expect(result, expectedRedirect);
      });

      test('should redirect to login page preserving the join link as redirect_to', () async {
        final joinUri = GroupDetailsPage.getInvitationLink('123');
        final result = await handleRedirect(
          joinUri,
          mockAuthService,
          userRepo: mockUserRepository,
        );
        final expectedRedirect =
            '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(joinUri)}';
        expect(result, expectedRedirect);
      });
    });

    group('user logged in', () {
      setUp(() {
        when(() => mockAuthService.currentUserId).thenReturn('test-uid');
        when(() => mockAuthService.currentUserEmail).thenReturn(null);
        when(() => mockAuthService.currentUserPhoneNumber).thenReturn(null);
      });

      group('user has no display name', () {
        setUp(() {
          when(
            () => mockUserRepository.getOrCreateUser(
              any(),
              email: any(named: 'email'),
              phoneNumber: any(named: 'phoneNumber'),
            ),
          ).thenAnswer((_) async => User(id: 'test-uid'));
        });

        test('should not redirect when on the profile page', () async {
          final result = await handleRedirect(
            ProfilePage.route,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, isNull);
        });

        test('should redirect to profile page from a protected page', () async {
          const initialRoute = HomePage.route; // This is '/'
          final result = await handleRedirect(
            initialRoute,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          final expectedRedirect =
              '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(initialRoute)}';
          expect(result, expectedRedirect);
        });

        test('should redirect to the profile page when signing in from the login page', () async {
          // A brand-new account signs in on /login; home has no user document
          // to render, so it must reach onboarding instead.
          final result = await handleRedirect(
            LoginPage.route,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, ProfilePage.route);
        });

        test('should send a new account to the profile page, preserving redirect_to', () async {
          final joinUri = GroupDetailsPage.getInvitationLink('123');
          final loginUriWithRedirect =
              '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(joinUri)}';
          final result = await handleRedirect(
            loginUriWithRedirect,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          final expectedRedirect =
              '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(joinUri)}';
          expect(result, expectedRedirect);
        });

        test('should redirect to profile page preserving the join link as redirect_to', () async {
          final joinUri = GroupDetailsPage.getInvitationLink('123');
          final result = await handleRedirect(
            joinUri,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          final expectedRedirect =
              '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(joinUri)}';
          expect(result, expectedRedirect);
        });

        test('should redirect to profile page preserving redirect_to from verify page', () async {
          final joinUri = GroupDetailsPage.getInvitationLink('123');
          final verifyUriWithRedirect =
              '${VerificationPage.route}?$redirectToParam=${Uri.encodeComponent(joinUri)}';
          final result = await handleRedirect(
            verifyUriWithRedirect,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          final expectedRedirect =
              '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(joinUri)}';
          expect(result, expectedRedirect);
        });
      });

      group('user has a display name', () {
        setUp(() {
          when(
            () => mockUserRepository.getOrCreateUser(
              any(),
              email: any(named: 'email'),
              phoneNumber: any(named: 'phoneNumber'),
            ),
          ).thenAnswer(
            (_) async => User(
              id: 'test-uid',
              email: 'test@test.com',
              displayName: 'Test User',
            ),
          );
        });

        test(
          'should redirect to home page when on login page without redirect',
          () async {
            final result = await handleRedirect(
              LoginPage.route,
              mockAuthService,
              userRepo: mockUserRepository,
            );
            expect(result, HomePage.route);
          },
        );

        test('should redirect to join link after login', () async {
          final joinUri = GroupDetailsPage.getInvitationLink('123');
          final loginUriWithRedirect =
              '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(joinUri)}';
          final result = await handleRedirect(
            loginUriWithRedirect,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, joinUri);
        });

        test('should redirect to join link after verification', () async {
          final joinUri = GroupDetailsPage.getInvitationLink('123');
          final verifyUriWithRedirect =
              '${VerificationPage.route}?$redirectToParam=${Uri.encodeComponent(joinUri)}';
          final result = await handleRedirect(
            verifyUriWithRedirect,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, joinUri);
        });

        test(
          'should not redirect from any other page (including join link)',
          () async {
            // From home
            var result = await handleRedirect(
              HomePage.route,
              mockAuthService,
              userRepo: mockUserRepository,
            );
            expect(result, isNull);

            // From join link
            result = await handleRedirect(
              GroupDetailsPage.getInvitationLink('123'),
              mockAuthService,
              userRepo: mockUserRepository,
            );
            expect(result, isNull);
          },
        );
      });
    });
  });

  group('handleRedirect repository resolution', () {
    test('uses the registered UserRepository when none is passed', () async {
      when(() => mockAuthService.currentUserId).thenReturn('test-uid');
      when(() => mockAuthService.currentUserEmail).thenReturn(null);
      when(() => mockAuthService.currentUserPhoneNumber).thenReturn(null);
      when(
        () => mockUserRepository.getOrCreateUser(
          any(),
          email: any(named: 'email'),
          phoneNumber: any(named: 'phoneNumber'),
        ),
      ).thenAnswer((_) async => User(id: 'test-uid', displayName: 'Sasha'));
      getIt.registerSingleton<UserRepository>(mockUserRepository);
      addTearDown(getIt.reset);

      final result = await handleRedirect(HomePage.route, mockAuthService);

      expect(result, isNull);
      verify(
        () => mockUserRepository.getOrCreateUser(
          'test-uid',
          email: null,
          phoneNumber: null,
        ),
      ).called(1);
    });
  });

  group('resolveUserRepository', () {
    test('uses the injected repository', () {
      final injected = MockUserRepository();

      expect(resolveUserRepository(injected), same(injected));
    });

    test('falls back to the registered repository', () {
      getIt.registerSingleton<UserRepository>(mockUserRepository);
      addTearDown(getIt.reset);

      expect(resolveUserRepository(), same(mockUserRepository));
    });
  });
}
