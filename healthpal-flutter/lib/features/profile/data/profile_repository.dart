import '../domain/user_profile.dart';
import '../../auth/domain/auth_user.dart';

enum ProfileFailure { conflict, validation, network, unknown }

class ProfileException implements Exception {
  const ProfileException(this.code, {this.message});

  final ProfileFailure code;
  final String? message;

  @override
  String toString() => 'ProfileException(${code.name})';
}

abstract interface class ProfileRepository {
  void ensure(AuthUser user);

  Future<UserProfile> fetch(String userId);

  Future<UserProfile> updateProfile(UserProfile profile);

  Future<UserProfile> updateSettings({
    required String userId,
    HealthGoal? goal,
    int? dailyStepGoal,
    bool? healthConnectSync,
    bool? autoSync,
    bool? wifiOnly,
    bool? experimentalFatigueConsent,
  });

  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  });
}
