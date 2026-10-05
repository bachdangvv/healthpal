import 'package:flutter_test/flutter_test.dart';
import 'package:healthpal/core/auth/secure_token_store.dart';

void main() {
  test('memory token store round-trips and clears', () async {
    final store = MemoryTokenStore();
    expect(await store.read(), isNull);
    await store.write(
      StoredTokens(
        accessToken: 'a',
        refreshToken: 'r',
        accessExpiresAtUtc: DateTime.utc(2026, 9, 30, 10),
        refreshExpiresAtUtc: DateTime.utc(2026, 10, 7),
      ),
    );
    final read = await store.read();
    expect(read?.accessToken, 'a');
    expect(read?.refreshToken, 'r');
    await store.clear();
    expect(await store.read(), isNull);
  });
}
