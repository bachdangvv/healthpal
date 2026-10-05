import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/dto/api_dtos.dart';
import '../../../core/database/device_settings_store.dart';
import '../../auth/domain/auth_user.dart';
import '../domain/user_profile.dart';
import 'profile_repository.dart';

class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository({
    required ApiClient client,
    DeviceSettingsStore? settingsStore,
  }) : _client = client,
       _settingsStore = settingsStore;

  final ApiClient _client;
  final DeviceSettingsStore? _settingsStore;
  final Map<String, UserProfile> _cache = {};

  @override
  void ensure(AuthUser user) {
    _cache.putIfAbsent(
      user.id,
      () => UserProfile(
        user: user,
        healthConnectStatus: HealthConnectStatus.unavailable,
      ),
    );
  }

  @override
  Future<UserProfile> fetch(String userId) async {
    try {
      final response = await _client.raw.get<Map<String, dynamic>>(
        '/api/v1/profile',
      );
      final dto = ProfileDto.fromJson(response.data!);
      final cached = _cache[userId];
      final local =
          await _settingsStore?.read(userId) ?? const DeviceSyncSettings();
      final profile = UserProfile(
        user:
            cached?.user ??
            AuthUser(
              id: dto.userId,
              name: dto.displayName,
              email: dto.email ?? '',
            ),
        birthDate: dto.birthDate,
        gender: dto.gender,
        heightCm: dto.heightCm,
        weightKg: dto.weightKg,
        goal: _goalFrom(dto.goal) ?? HealthGoal.maintainHealth,
        dailyStepGoal: dto.dailyStepGoal,
        healthConnectSync: local.healthConnectSync,
        autoSync: local.autoSync,
        wifiOnly: local.wifiOnly,
        healthConnectStatus:
            cached?.healthConnectStatus ?? HealthConnectStatus.unavailable,
        rowVersion: dto.rowVersion,
        experimentalFatigueConsent: dto.experimentalFatigueConsent,
      );
      _cache[userId] = profile;
      return profile;
    } on DioException catch (error) {
      final mapped = _map(error);
      final cached = _cache[userId];
      if (cached != null &&
          (mapped.code == ProfileFailure.network ||
              mapped.code == ProfileFailure.unknown)) {
        final local =
            await _settingsStore?.read(userId) ?? const DeviceSyncSettings();
        final fallback = cached.copyWith(
          healthConnectSync: local.healthConnectSync,
          autoSync: local.autoSync,
          wifiOnly: local.wifiOnly,
        );
        _cache[userId] = fallback;
        return fallback;
      }
      throw mapped;
    }
  }

  @override
  Future<UserProfile> updateProfile(UserProfile profile) async {
    final version = profile.rowVersion;
    if (version == null || version.isEmpty) {
      throw const ProfileException(
        ProfileFailure.validation,
        message: 'Row version is required',
      );
    }
    try {
      final response = await _client.raw.put<Map<String, dynamic>>(
        '/api/v1/profile',
        data: {
          'displayName': profile.user.name,
          'birthDate': profile.birthDate == null
              ? null
              : '${profile.birthDate!.year.toString().padLeft(4, '0')}-${profile.birthDate!.month.toString().padLeft(2, '0')}-${profile.birthDate!.day.toString().padLeft(2, '0')}',
          'gender': profile.gender,
          'heightCm': profile.heightCm,
          'weightKg': profile.weightKg,
          'goal': profile.goal.name,
          'dailyStepGoal': profile.dailyStepGoal,
          'experimentalFatigueConsent': profile.experimentalFatigueConsent,
          'rowVersion': version,
        },
      );
      return _cacheFromDto(profile.user, response.data!, profile);
    } on DioException catch (error) {
      throw _map(error);
    }
  }

  @override
  Future<UserProfile> updateSettings({
    required String userId,
    HealthGoal? goal,
    int? dailyStepGoal,
    bool? healthConnectSync,
    bool? autoSync,
    bool? wifiOnly,
    bool? experimentalFatigueConsent,
  }) async {
    final current = _cache[userId];
    if (current == null) throw StateError('Profile not found');
    final hasServer =
        goal != null ||
        dailyStepGoal != null ||
        experimentalFatigueConsent != null;
    final hasDevice =
        healthConnectSync != null || autoSync != null || wifiOnly != null;
    var updated = current.copyWith(
      healthConnectSync: healthConnectSync,
      autoSync: autoSync,
      wifiOnly: wifiOnly,
    );
    if (hasServer) {
      final version = current.rowVersion;
      if (version == null || version.isEmpty) {
        throw const ProfileException(
          ProfileFailure.validation,
          message: 'Row version is required',
        );
      }
      try {
        final response = await _client.raw.put<Map<String, dynamic>>(
          '/api/v1/profile/preferences',
          data: {
            'goal': (goal ?? current.goal).name,
            'dailyStepGoal': dailyStepGoal ?? current.dailyStepGoal,
            'experimentalFatigueConsent':
                experimentalFatigueConsent ??
                current.experimentalFatigueConsent,
            'rowVersion': version,
          },
        );
        updated = _cacheFromDto(current.user, response.data!, updated);
      } on DioException catch (error) {
        throw _map(error);
      }
    }
    if (hasDevice) {
      await _settingsStore?.write(
        userId,
        DeviceSyncSettings(
          healthConnectSync: updated.healthConnectSync,
          autoSync: updated.autoSync,
          wifiOnly: updated.wifiOnly,
        ),
      );
    }
    _cache[userId] = updated;
    return updated;
  }

  @override
  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _client.raw.post<void>(
        '/api/v1/auth/change-password',
        data: {'currentPassword': currentPassword, 'newPassword': newPassword},
      );
    } on DioException catch (error) {
      throw _map(error);
    }
  }

  UserProfile _cacheFromDto(
    AuthUser user,
    Map<String, dynamic> json,
    UserProfile fallback,
  ) {
    final dto = ProfileDto.fromJson(json);
    final profile = fallback.copyWith(
      user: AuthUser(id: user.id, name: dto.displayName, email: user.email),
      birthDate: dto.birthDate,
      gender: dto.gender,
      heightCm: dto.heightCm,
      weightKg: dto.weightKg,
      goal: _goalFrom(dto.goal) ?? fallback.goal,
      dailyStepGoal: dto.dailyStepGoal,
      rowVersion: dto.rowVersion,
      experimentalFatigueConsent: dto.experimentalFatigueConsent,
    );
    _cache[user.id] = profile;
    return profile;
  }

  ProfileException _map(DioException error) {
    final status = error.response?.statusCode ?? 0;
    if (status == 409 || status == 412) {
      return const ProfileException(ProfileFailure.conflict);
    }
    if (status >= 400 && status < 500) {
      return const ProfileException(ProfileFailure.validation);
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return const ProfileException(ProfileFailure.network);
    }
    return const ProfileException(ProfileFailure.unknown);
  }

  HealthGoal? _goalFrom(String? value) {
    if (value == null) return null;
    for (final goal in HealthGoal.values) {
      if (goal.name == value) return goal;
    }
    return null;
  }
}
