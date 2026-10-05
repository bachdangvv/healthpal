import 'package:flutter/foundation.dart';

import '../../auth/domain/auth_user.dart';
import '../data/profile_repository.dart';
import '../domain/user_profile.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({
    required this.repository,
    required this.userId,
    this.user,
  });

  final ProfileRepository repository;
  final String userId;
  final AuthUser? user;
  UserProfile? _profile;
  Object? _error;
  bool _loading = false;
  bool _saving = false;

  UserProfile? get profile => _profile;
  Object? get error => _error;
  bool get isLoading => _loading;
  bool get isSaving => _saving;
  bool get canSave =>
      _profile != null &&
      _profile!.rowVersion != null &&
      _profile!.rowVersion!.isNotEmpty;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _profile = await repository.fetch(userId);
    } catch (error) {
      _error = error;
      _profile ??= UserProfile(
        user: user ?? AuthUser(id: userId, name: '', email: ''),
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> save(UserProfile profile) async {
    if (_saving) return false;
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      _profile = await repository.updateProfile(profile);
      return true;
    } on ProfileException catch (error) {
      _error = error;
      if (error.code == ProfileFailure.conflict) {
        try {
          _profile = await repository.fetch(userId);
        } catch (_) {}
      }
      return false;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<bool> updateSettings({
    HealthGoal? goal,
    int? dailyStepGoal,
    bool? healthConnectSync,
    bool? autoSync,
    bool? wifiOnly,
    bool? experimentalFatigueConsent,
  }) async {
    if (_saving || _profile == null) return false;
    _saving = true;
    notifyListeners();
    try {
      _profile = await repository.updateSettings(
        userId: userId,
        goal: goal,
        dailyStepGoal: dailyStepGoal,
        healthConnectSync: healthConnectSync,
        autoSync: autoSync,
        wifiOnly: wifiOnly,
        experimentalFatigueConsent: experimentalFatigueConsent,
      );
      return true;
    } on ProfileException catch (error) {
      _error = error;
      if (error.code == ProfileFailure.conflict) {
        try {
          _profile = await repository.fetch(userId);
        } catch (_) {}
      }
      return false;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_saving) return false;
    _saving = true;
    _error = null;
    notifyListeners();
    try {
      await repository.changePassword(
        userId: userId,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return true;
    } catch (error) {
      _error = error;
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}
