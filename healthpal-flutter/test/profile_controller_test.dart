import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/features/auth/domain/auth_user.dart';
import 'package:healthpal/features/profile/application/profile_controller.dart';
import 'package:healthpal/features/profile/data/demo_profile_repository.dart';
import 'package:healthpal/features/profile/domain/user_profile.dart';

void main() {
  const user = AuthUser(
    id: 'profile-test',
    name: 'Minh Anh',
    email: 'demo@healthpal.app',
  );

  test('loads and updates profile settings in the demo repository', () async {
    final repository = DemoProfileRepository();
    repository.ensure(user);
    final controller = ProfileController(
      repository: repository,
      userId: user.id,
    );

    await controller.load();
    expect(controller.profile?.dailyStepGoal, 8000);

    final saved = await controller.save(
      controller.profile!.copyWith(
        user: AuthUser(id: user.id, name: 'Tên mới', email: user.email),
        goal: HealthGoal.buildMuscle,
      ),
    );
    expect(saved, isTrue);
    expect(controller.profile?.user.name, 'Tên mới');
    expect(controller.profile?.goal, HealthGoal.buildMuscle);

    await controller.updateSettings(
      dailyStepGoal: 10000,
      healthConnectSync: true,
      wifiOnly: true,
    );
    expect(controller.profile?.dailyStepGoal, 10000);
    expect(controller.profile?.healthConnectSync, isTrue);
    expect(controller.profile?.wifiOnly, isTrue);
  });
}
