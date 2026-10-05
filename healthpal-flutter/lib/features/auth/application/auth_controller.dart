import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/auth_repository.dart';
import '../domain/auth_user.dart';

class AuthController extends ChangeNotifier {
  AuthController({
    required AuthRepository repository,
    bool restoreOnStart = false,
  }) : _repository = repository {
    if (restoreOnStart) {
      _restoring = true;
      unawaited(restoreSession());
    }
  }

  final AuthRepository _repository;
  AuthUser? _user;
  AuthException? _error;
  bool _isBusy = false;
  bool _restoring = false;
  bool _isDisposed = false;

  AuthUser? get user => _user;
  AuthException? get error => _error;
  bool get isBusy => _isBusy;
  bool get isRestoring => _restoring;

  Future<void> restoreSession() async {
    if (_isDisposed) return;
    _restoring = true;
    _error = null;
    notifyListeners();
    try {
      final user = await _repository.restoreSession();
      if (_isDisposed) return;
      _user = user;
    } on AuthException catch (error) {
      if (!_isDisposed) _error = error;
    } catch (_) {
      if (!_isDisposed) _error = const AuthException(AuthFailure.unknown);
    } finally {
      if (!_isDisposed) {
        _restoring = false;
        notifyListeners();
      }
    }
  }

  Future<bool> signIn({required String email, required String password}) =>
      _run(() => _repository.signIn(email: email, password: password));

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
  }) => _run(
    () => _repository.signUp(name: name, email: email, password: password),
  );

  Future<bool> signOut() => _run(() async {
    await _repository.signOut();
    return null;
  });

  void clearError() {
    if (_isDisposed || _error == null) return;
    _error = null;
    notifyListeners();
  }

  void updateDisplayName(String name) {
    if (_isDisposed || _user == null || name.trim().isEmpty) return;
    _user = AuthUser(id: _user!.id, name: name.trim(), email: _user!.email);
    notifyListeners();
  }

  Future<bool> _run(Future<AuthUser?> Function() operation) async {
    if (_isDisposed || _isBusy || _restoring) return false;
    _isBusy = true;
    _error = null;
    notifyListeners();

    try {
      final user = await operation();
      if (_isDisposed) return false;
      _user = user;
      return true;
    } on AuthException catch (error) {
      if (!_isDisposed) _error = error;
      return false;
    } catch (_) {
      if (!_isDisposed) _error = const AuthException(AuthFailure.unknown);
      return false;
    } finally {
      if (!_isDisposed) {
        _isBusy = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _isBusy = false;
    super.dispose();
  }
}
