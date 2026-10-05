import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/api/api_client.dart';
import 'package:healthpal/core/auth/secure_token_store.dart';
import 'package:healthpal/core/database/device_settings_store.dart';
import 'package:healthpal/core/database/healthpal_database.dart';
import 'package:healthpal/features/auth/domain/auth_user.dart';
import 'package:healthpal/features/profile/data/api_profile_repository.dart';
import 'package:healthpal/features/profile/domain/user_profile.dart';

const user = AuthUser(id: 'user-a', name: 'A', email: 'a@example.com');

class _ProfileAdapter implements HttpClientAdapter {
  bool throwOnPut = false;
  int puts = 0;
  int gets = 0;
  String rowVersion = 'rv-1';
  bool consent = false;
  String goal = 'maintainHealth';
  int dailyStepGoal = 8000;
  String lastPath = '';

  Map<String, dynamic> profileJson() => {
    'userId': user.id,
    'displayName': user.name,
    'email': user.email,
    'goal': goal,
    'dailyStepGoal': dailyStepGoal,
    'rowVersion': rowVersion,
    'experimentalFatigueConsent': consent,
  };

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastPath = '${options.method} ${options.path}';
    if (options.method == 'GET') {
      gets += 1;
      return ResponseBody.fromString(
        jsonEncode(profileJson()),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.method == 'PUT') {
      puts += 1;
      if (throwOnPut) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      if (requestStream != null) {
        final chunks = await requestStream.toList();
        final body = utf8.decode(chunks.expand((chunk) => chunk).toList());
        final json = jsonDecode(body) as Map<String, dynamic>;
        consent = json['experimentalFatigueConsent'] as bool? ?? consent;
        goal = json['goal'] as String? ?? goal;
        dailyStepGoal = json['dailyStepGoal'] as int? ?? dailyStepGoal;
      }
      rowVersion = 'rv-${puts + 1}';
      return ResponseBody.fromString(
        jsonEncode(profileJson()),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{}', 404);
  }

  @override
  void close({bool force = false}) {}
}

(ApiProfileRepository, _ProfileAdapter, HealthPalDatabase) repo() {
  final db = HealthPalDatabase.memory();
  final adapter = _ProfileAdapter();
  final dio = Dio(BaseOptions(baseUrl: 'http://example.test'));
  dio.httpClientAdapter = adapter;
  final repository = ApiProfileRepository(
    client: ApiClient(tokenStore: MemoryTokenStore(), dio: dio),
    settingsStore: DeviceSettingsStore(db),
  );
  repository.ensure(user);
  return (repository, adapter, db);
}

void main() {
  test('device-only update succeeds when the backend throws', () async {
    final (repository, adapter, db) = repo();
    addTearDown(db.dispose);
    adapter.throwOnPut = true;
    final updated = await repository.updateSettings(
      userId: user.id,
      healthConnectSync: true,
      autoSync: false,
      wifiOnly: true,
    );
    expect(updated.healthConnectSync, isTrue);
    expect(updated.autoSync, isFalse);
    expect(updated.wifiOnly, isTrue);
    expect(adapter.puts, 0);
  });

  test('device-only update creates zero HTTP calls', () async {
    final (repository, adapter, db) = repo();
    addTearDown(db.dispose);
    await repository.updateSettings(userId: user.id, wifiOnly: true);
    expect(adapter.puts, 0);
    expect(adapter.gets, 0);
  });

  test('device settings survive repository recreate', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final store = DeviceSettingsStore(db);
    await store.write(
      user.id,
      const DeviceSyncSettings(
        healthConnectSync: true,
        autoSync: false,
        wifiOnly: true,
      ),
    );
    final reread = DeviceSettingsStore(db);
    final settings = await reread.read(user.id);
    expect(settings.healthConnectSync, isTrue);
    expect(settings.autoSync, isFalse);
    expect(settings.wifiOnly, isTrue);
  });

  test('device settings are isolated per user', () async {
    final db = HealthPalDatabase.memory();
    addTearDown(db.dispose);
    final store = DeviceSettingsStore(db);
    await store.write(
      'a',
      const DeviceSyncSettings(healthConnectSync: true, wifiOnly: true),
    );
    await store.write('b', const DeviceSyncSettings(autoSync: false));
    expect((await store.read('a')).healthConnectSync, isTrue);
    expect((await store.read('a')).wifiOnly, isTrue);
    expect((await store.read('b')).healthConnectSync, isFalse);
    expect((await store.read('b')).autoSync, isFalse);
  });

  test(
    'consent-only update makes one HTTP call and leaves device settings',
    () async {
      final (repository, adapter, db) = repo();
      addTearDown(db.dispose);
      await DeviceSettingsStore(db).write(
        user.id,
        const DeviceSyncSettings(
          healthConnectSync: true,
          autoSync: true,
          wifiOnly: true,
        ),
      );
      await repository.fetch(user.id);
      adapter.puts = 0;
      adapter.gets = 0;
      final updated = await repository.updateSettings(
        userId: user.id,
        experimentalFatigueConsent: true,
      );
      expect(adapter.puts, 1);
      expect(adapter.gets, 0);
      expect(updated.experimentalFatigueConsent, isTrue);
      final local = await DeviceSettingsStore(db).read(user.id);
      expect(local.healthConnectSync, isTrue);
      expect(local.autoSync, isTrue);
      expect(local.wifiOnly, isTrue);
    },
  );

  test('goal update sends rowVersion and caches the new version', () async {
    final (repository, adapter, db) = repo();
    addTearDown(db.dispose);
    await repository.fetch(user.id);
    final updated = await repository.updateSettings(
      userId: user.id,
      goal: HealthGoal.loseWeight,
      dailyStepGoal: 9000,
    );
    expect(adapter.puts, 1);
    expect(updated.rowVersion, 'rv-2');
    expect(updated.dailyStepGoal, 9000);
  });

  test('device-only update does not require a rowVersion', () async {
    final (repository, adapter, db) = repo();
    addTearDown(db.dispose);
    expect(repository, isA<ApiProfileRepository>());
    final updated = await repository.updateSettings(
      userId: user.id,
      autoSync: false,
    );
    expect(updated.autoSync, isFalse);
    expect(adapter.puts, 0);
  });
}
