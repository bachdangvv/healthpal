import '../domain/auth_user.dart';
import 'auth_repository.dart';

/// In-memory demonstration only. Credentials are never persisted or sent out.
/// Production authentication belongs in an API-backed [AuthRepository].
class DemoAuthRepository implements AuthRepository {
  DemoAuthRepository({this.latency = const Duration(milliseconds: 600)}) {
    _accounts[demoEmail] = (
      user: const AuthUser(id: 'demo', name: demoName, email: demoEmail),
      password: demoPassword,
    );
  }

  static const demoEmail = 'demo@healthpal.app';
  static const demoPassword = 'HealthPal123';
  static const demoName = 'Minh Anh';

  final Duration latency;
  final Map<String, ({AuthUser user, String password})> _accounts = {};
  int _nextId = 1;

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(latency);
    final account = _accounts[_normalizeEmail(email)];
    if (account == null || account.password != password) {
      throw const AuthException(AuthFailure.invalidCredentials);
    }
    return account.user;
  }

  @override
  Future<AuthUser> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(latency);
    final normalizedEmail = _normalizeEmail(email);
    if (_accounts.containsKey(normalizedEmail)) {
      throw const AuthException(AuthFailure.emailAlreadyInUse);
    }
    final user = AuthUser(
      id: 'user-${_nextId++}',
      name: name.trim(),
      email: normalizedEmail,
    );
    _accounts[normalizedEmail] = (user: user, password: password);
    return user;
  }

  @override
  Future<void> signOut() => Future<void>.delayed(latency);

  @override
  Future<AuthUser?> restoreSession() async {
    await Future<void>.delayed(latency);
    return null;
  }
}
