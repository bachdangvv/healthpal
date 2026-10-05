import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/features/auth/application/auth_controller.dart';
import 'package:healthpal/features/auth/data/auth_repository.dart';
import 'package:healthpal/features/auth/data/demo_auth_repository.dart';
import 'package:healthpal/features/auth/domain/auth_user.dart';

void main() {
  group('Demo authentication', () {
    late AuthController controller;

    setUp(() {
      controller = AuthController(
        repository: DemoAuthRepository(latency: Duration.zero),
      );
    });

    tearDown(() => controller.dispose());

    test('starts signed out and signs in with normalized demo email', () async {
      expect(controller.user, isNull);
      expect(controller.isBusy, isFalse);
      expect(
        await controller.signIn(
          email: '  DEMO@HealthPal.app  ',
          password: DemoAuthRepository.demoPassword,
        ),
        isTrue,
      );
      expect(controller.user?.name, 'Minh Anh');
      expect(controller.user?.email, DemoAuthRepository.demoEmail);
      expect(controller.error, isNull);
    });

    test('new account survives logout and accepts normalized email', () async {
      expect(
        await controller.signUp(
          name: '  An Nguyễn  ',
          email: '  AN@example.com ',
          password: 'MyPassword123',
        ),
        isTrue,
      );
      final userId = controller.user!.id;
      expect(controller.user?.name, 'An Nguyễn');
      expect(controller.user?.email, 'an@example.com');
      expect(await controller.signOut(), isTrue);
      expect(controller.user, isNull);
      expect(
        await controller.signIn(
          email: 'AN@example.com',
          password: 'MyPassword123',
        ),
        isTrue,
      );
      expect(controller.user?.id, userId);
    });

    test('registration rejects duplicate normalized email', () async {
      expect(
        await controller.signUp(
          name: 'Other Name',
          email: '  DEMO@HEALTHPAL.APP ',
          password: 'OtherPassword123',
        ),
        isFalse,
      );
      expect(controller.error?.code, AuthFailure.emailAlreadyInUse);
      expect(controller.user, isNull);
    });

    test('wrong email and password report the same credential error', () async {
      for (final credentials in [
        (email: 'missing@example.com', password: 'HealthPal123'),
        (email: DemoAuthRepository.demoEmail, password: 'WrongPassword'),
      ]) {
        expect(
          await controller.signIn(
            email: credentials.email,
            password: credentials.password,
          ),
          isFalse,
        );
        expect(controller.error?.code, AuthFailure.invalidCredentials);
        expect(controller.user, isNull);
        expect(controller.isBusy, isFalse);
        controller.clearError();
        expect(controller.error, isNull);
      }
    });

    test('password whitespace is preserved', () async {
      await controller.signUp(
        name: 'An',
        email: 'an@example.com',
        password: ' Password123 ',
      );
      await controller.signOut();
      expect(
        await controller.signIn(
          email: 'an@example.com',
          password: 'Password123',
        ),
        isFalse,
      );
      expect(
        await controller.signIn(
          email: 'an@example.com',
          password: ' Password123 ',
        ),
        isTrue,
      );
    });

    test('a fresh repository resets registered accounts', () async {
      await controller.signUp(
        name: 'An',
        email: 'an@example.com',
        password: 'Password123',
      );
      final fresh = AuthController(
        repository: DemoAuthRepository(latency: Duration.zero),
      );
      addTearDown(fresh.dispose);
      expect(
        await fresh.signIn(email: 'an@example.com', password: 'Password123'),
        isFalse,
      );
      expect(fresh.user, isNull);
    });
  });

  group('Controller lifecycle', () {
    test('only one repository request may run at a time', () async {
      final repository = _ControlledRepository();
      final controller = AuthController(repository: repository);
      addTearDown(controller.dispose);
      final pending = controller.signIn(email: 'a@b.com', password: 'Password');
      expect(controller.isBusy, isTrue);
      expect(
        await controller.signIn(email: 'a@b.com', password: 'Password'),
        isFalse,
      );
      expect(await controller.signOut(), isFalse);
      expect(repository.signInCalls, 1);
      expect(repository.signOutCalls, 0);
      repository.signInResult.complete(_testUser);
      expect(await pending, isTrue);
      expect(controller.isBusy, isFalse);
      expect(controller.user, _testUser);
    });

    test('completion after disposal does not notify or set a user', () async {
      final repository = _ControlledRepository();
      final controller = AuthController(repository: repository);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final pending = controller.signIn(email: 'a@b.com', password: 'Password');
      expect(notifications, 1);
      controller.dispose();
      repository.signInResult.complete(_testUser);
      expect(await pending, isFalse);
      expect(notifications, 1);
      expect(controller.user, isNull);
      expect(await controller.signOut(), isFalse);
    });

    test('unexpected errors become unknown without exposing details', () async {
      final repository = _ControlledRepository();
      final controller = AuthController(repository: repository);
      addTearDown(controller.dispose);
      final pending = controller.signIn(email: 'a@b.com', password: 'Password');
      repository.signInResult.completeError(StateError('Internal details'));
      expect(await pending, isFalse);
      expect(controller.error?.code, AuthFailure.unknown);
      expect(controller.isBusy, isFalse);
    });

    test('restoreOnStart opens a session without a login call', () async {
      final repository = _ControlledRepository()..restoreUser = _testUser;
      final controller = AuthController(
        repository: repository,
        restoreOnStart: true,
      );
      addTearDown(controller.dispose);
      expect(controller.isRestoring, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(controller.user, _testUser);
      expect(controller.isRestoring, isFalse);
      expect(repository.signInCalls, 0);
    });

    test('network restore errors stay retryable', () async {
      final repository = _ControlledRepository()..failRestoreNetwork = true;
      final controller = AuthController(repository: repository);
      addTearDown(controller.dispose);
      await controller.restoreSession();
      expect(controller.user, isNull);
      expect(controller.error?.code, AuthFailure.network);
    });

    test('failed sign-out retains the authenticated user', () async {
      final repository = _ControlledRepository();
      final controller = AuthController(repository: repository);
      addTearDown(controller.dispose);
      final pending = controller.signIn(email: 'a@b.com', password: 'Password');
      repository.signInResult.complete(_testUser);
      await pending;
      repository.failSignOut = true;
      expect(await controller.signOut(), isFalse);
      expect(controller.user, _testUser);
      expect(controller.error?.code, AuthFailure.unknown);
    });
  });
}

const _testUser = AuthUser(id: 'test', name: 'Test', email: 'a@b.com');

class _ControlledRepository implements AuthRepository {
  final signInResult = Completer<AuthUser>();
  var signInCalls = 0;
  var signOutCalls = 0;
  var failSignOut = false;
  AuthUser? restoreUser;
  var failRestoreNetwork = false;

  @override
  Future<AuthUser> signIn({required String email, required String password}) {
    signInCalls++;
    return signInResult.future;
  }

  @override
  Future<AuthUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async => _testUser;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (failSignOut) throw StateError('Unable to sign out');
  }

  @override
  Future<AuthUser?> restoreSession() async {
    if (failRestoreNetwork) {
      throw const AuthException(AuthFailure.network);
    }
    return restoreUser;
  }
}
