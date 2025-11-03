import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/domain/user.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import 'package:wishtogether/features/auth/presentation/login_page.dart';
import 'package:wishtogether/features/auth/presentation/profile_page.dart';

class MockAuthService extends Mock implements AuthService {}

class MockUserRepository extends Mock implements UserRepository {}

class MockFirebaseUser extends Mock implements firebase_auth.User {
  @override
  final String uid = 'test-uid';
  @override
  final String? email = 'test@test.com';
}

void main() {
  late MockAuthService mockAuthService;
  late MockUserRepository mockUserRepository;
  late MockFirebaseUser mockFirebaseUser;

  setUp(() {
    mockAuthService = MockAuthService();
    mockUserRepository = MockUserRepository();
    mockFirebaseUser = MockFirebaseUser();
  });

  group('handleRedirect', () {
    group('user not logged in', () {
      setUp(() {
        when(() => mockAuthService.currentUser).thenReturn(null);
      });

      test('should not redirect when on the login page', () async {
        final result = await handleRedirect(
          LoginPage.route,
          mockAuthService,
          userRepo: mockUserRepository,
        );
        expect(result, isNull);
      });

      test('should redirect to the login page from any other page', () async {
        final result = await handleRedirect(
          HomePage.route,
          mockAuthService,
          userRepo: mockUserRepository,
        );
        expect(result, LoginPage.route);
      });
    });

    group('user logged in', () {
      setUp(() {
        when(() => mockAuthService.currentUser).thenReturn(mockFirebaseUser);
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

        test('should not redirect when creating a profile', () async {
          final result = await handleRedirect(
            ProfilePage.route,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, isNull);
        });

        test('should redirect to profile page from any other page', () async {
          final result = await handleRedirect(
            HomePage.route,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, ProfilePage.route);
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

        test('should redirect to home page when on login page', () async {
          final result = await handleRedirect(
            LoginPage.route,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, HomePage.route);
        });

        test('should not redirect from any other page', () async {
          final result = await handleRedirect(
            HomePage.route,
            mockAuthService,
            userRepo: mockUserRepository,
          );
          expect(result, isNull);
        });
      });
    });
  });
}
