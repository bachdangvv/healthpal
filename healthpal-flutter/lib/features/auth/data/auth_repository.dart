import '../domain/auth_user.dart';

enum AuthFailure { invalidCredentials, emailAlreadyInUse, network, unknown }

class AuthException implements Exception {
  const AuthException(this.code);

  final AuthFailure code;

  @override
  String toString() => 'AuthException(${code.name})';
}

/// Replace the demo implementation with an API-backed repository when ready.
abstract interface class AuthRepository {
  Future<AuthUser> signIn({required String email, required String password});

  Future<AuthUser> signUp({
    required String name,
    required String email,
    required String password,
  });

  Future<void> signOut();

  Future<AuthUser?> restoreSession();
}
