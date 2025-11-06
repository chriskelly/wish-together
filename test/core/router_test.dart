import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/auth/presentation/login_page.dart';
import 'package:wishtogether/features/auth/presentation/profile_page.dart';
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

      test('should redirect to login page from a protected page with redirect',
          () async {
        const initialRoute = HomePage.route; // This is '/'
        final result = await handleRedirect(
          initialRoute,
          mockAuthService,
          userRepo: mockUserRepository,
        );
        final expectedRedirect = '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(initialRoute)}';
        expect(result, expectedRedirect);
      });

      test(
          'should redirect to login page preserving the join link as redirect_to', () async {
        final joinUri = GroupDetailsPage.getInvitationLink('123');
        final result = await handleRedirect(
          joinUri,
          mockAuthService,
          userRepo: mockUserRepository,
        );
        final expectedRedirect = '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(joinUri)}';
        expect(result, expectedRedirect);
      });
    });

    group('user logged in', () {
      setUp(() {
        when(() => mockAuthService.currentUserId).thenReturn('test-uid');
        when(() => mockAuthService.currentUserEmail).thenReturn('test@test.com');
      });

      group('user has no display name', () {
        setUp(() {
          when(
            () => mockUserRepository.getOrCreateUser(
              any(),
              email: any(named: 'email'),
            ),
          ).thenAnswer(
            (_) async => User(id: 'test-uid', email: 'test@test.com'),
          );
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

        test(
            'should redirect to profile page preserving the join link as redirect_to', () async {
          final joinUri = GroupDetailsPage.getInvitationLink('123');
          final result = await handleRedirect(
            joinUri,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          final expectedRedirect = '${ProfilePage.route}?$redirectToParam=${Uri.encodeComponent(joinUri)}';
          expect(result, expectedRedirect);
        });
      });

      group('user has a display name', () {
        setUp(() {
          when(
            () => mockUserRepository.getOrCreateUser(
              any(),
              email: any(named: 'email'),
            ),
          ).thenAnswer(
            (_) async => User(
              id: 'test-uid',
              email: 'test@test.com',
              displayName: 'Test User',
            ),
          );
        });

        test('should redirect to home page when on login page without redirect', () async {
          final result = await handleRedirect(
            LoginPage.route,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, HomePage.route);
        });

        test('should redirect to join link after login', () async {
          final joinUri = GroupDetailsPage.getInvitationLink('123');
          final loginUriWithRedirect = '${LoginPage.route}?$redirectToParam=${Uri.encodeComponent(joinUri)}';
          final result = await handleRedirect(
            loginUriWithRedirect,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, joinUri);
        });

        test('should not redirect from any other page (including join link)', () async {
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
        });
      });
    });
  });
}