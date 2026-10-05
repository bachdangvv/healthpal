# HealthPal

Ứng dụng Flutter bằng tiếng Việt, ưu tiên Android. Giao diện hồng–tím, thẻ trắng bo tròn; hỗ trợ màn hình nhỏ và cỡ chữ lớn.

Thứ tự tab: **Tổng quan → Tập luyện → Lịch sử → Hồ sơ**. Màn Tập luyện giữ thuật toán readiness hiện tại; fatigue V4 là tín hiệu thử nghiệm, không phải chẩn đoán y tế.

## Chạy ứng dụng

```powershell
flutter pub get

# Emulator debug
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080 --dart-define=ENABLE_EXPERIMENTAL_FATIGUE=true

# Physical phone debug; thay bằng IP LAN thật tại thời điểm chạy
flutter run --dart-define=API_BASE_URL=http://<HOST_LAN_IP>:5080 --dart-define=ENABLE_EXPERIMENTAL_FATIGUE=true

# Release; phải là endpoint HTTPS thật
flutter build apk --release --dart-define=API_BASE_URL=https://<DEPLOYED_API_HOST>
```

Điện thoại và máy backend phải cùng mạng khi dùng LAN. Firewall phải cho phép cổng 5080 trong dev. `10.0.2.2` chỉ dùng cho emulator, không dùng cho máy thật. Debug variant cho phép HTTP cleartext; release không bật cleartext. Không hard-code IP LAN vào source. Release chưa có HTTPS endpoint thì chưa backend-ready.

| Dart define | Ý nghĩa | Mặc định dev |
|---|---|---|
| `API_BASE_URL` | Base URL backend ASP.NET | `http://10.0.2.2:5080` (emulator → host) |
| `ENABLE_EXPERIMENTAL_FATIGUE` | Feature flag `experimentalFatigueAssessment` | `true` cho bản demo nhóm; đặt `false` khi phát hành ngoài nhóm thử nghiệm |

Không hard-code secret hoặc token. Access/refresh token được lưu qua `flutter_secure_storage`, không ghi vào SQLite.

Android production composition (`AppDependencies.production()`) dùng API auth/profile, SQLite theo `userId` đã đăng nhập, Health Connect và V4. Demo repository chỉ dùng cho widget test, iOS và các nền tảng không phải Android. Seed backend Development: **demo@healthpal.app** / **HealthPal123**.

## Cấu trúc

- `lib/app.dart`: khởi tạo ứng dụng và vòng đời bộ điều khiển tài khoản.
- `lib/theme/`: màu sắc và kiểu giao diện dùng chung.
- `lib/features/auth/domain/`: thông tin người dùng.
- `lib/features/auth/data/`: hợp đồng AuthRepository và bản demo lưu trong bộ nhớ.
- `lib/features/auth/application/`: AuthController, trạng thái xử lý và lỗi.
- `lib/features/auth/presentation/`: đăng nhập, đăng ký, tài khoản và thành phần dùng chung.
- `lib/features/history/domain/`: health summary, khoảng thời gian, chỉ số và mức stress.
- `lib/features/history/data/`: hợp đồng repository và bộ dữ liệu demo 30 ngày.
- `lib/features/history/application/`: trạng thái tải, khoảng thời gian và chỉ số đang chọn.
- `lib/features/history/presentation/`: màn History & Analytics, biểu đồ và chi tiết ngày.
- `lib/core/config/`: `API_BASE_URL`, feature flag fatigue, `schemaVersion`.
- `lib/core/api/dto/`: DTO HTTP độc lập với widget model.
- `lib/core/sync/`: `SyncState` và outbox contract.
- `lib/features/assessment/domain/`: `FatigueAssessment` (không phụ thuộc training).
- `lib/features/health_connect/domain/`: record chuẩn hóa, permission, failure typed.
- `lib/features/home/presentation/`: shell IndexedStack, tab Tổng quan → Tập luyện → Lịch sử → Hồ sơ.
- `lib/features/profile/domain/`: hồ sơ, mục tiêu, `rowVersion` và trạng thái Health Connect.
- `lib/features/profile/data/`: `ApiProfileRepository` (production) và demo cho test.
- `lib/features/profile/application/`: ProfileController cho tải/lưu hồ sơ, cài đặt thiết bị và đổi mật khẩu.
- `lib/features/profile/presentation/`: màn Profile & Settings, đổi mật khẩu API và đăng xuất.
- `lib/core/user_health_runtime.dart`: runtime theo user sau login/restore.

Android production: Health Connect → canonicalize → aggregate → SQLite → V4 `assess()` → outbox → Dashboard/History. WorkManager không được register trong `main()`; scheduler reconcile sau login khi đủ quyền background.

## Kiểm tra

Android toolchain is pinned to Flutter 3.38's tested set: **AGP 8.11.1**, **Kotlin 2.2.20**, **Gradle 8.14**. AGP 9.1 / Kotlin 2.4 / Gradle 9.3 failed plugin compilation (`device_info_plus` expects built-in Kotlin on AGP 9, while this app keeps `android.builtInKotlin=false`).

Background Health Connect work uses unique WorkManager name `healthpal-health-sync-<userId>`, minimum periodic interval per WorkManager, unmetered-only when Wi-Fi-only is enabled, and is registered only after login when Health Connect sync, auto-sync, and background-read permission are all granted.

```sh
flutter analyze
flutter test
cd rust && cargo test --all-features && cargo clippy --all-targets --all-features -- -D warnings
flutter build apk --debug
flutter build apk --release
```

Fixture Health Connect: `test/fixtures/health_connect/{granted,missing_permission,no_data,stale_data}.json`.
Golden 48h: `test/fixtures/golden/user_48h_health_records.json`.

### Baseline (FND-01)

Lệnh bắt buộc: `flutter analyze`, `flutter test`, `flutter build apk --debug`.

Known issues đã xử lý khi khóa baseline trên Flutter 3.38.7 / Dart 3.10.7:

- `environment.sdk` nới từ `^3.13.3` xuống `^3.10.0` để khớp toolchain máy triển khai.
- `AuthController` không còn named parameter `_repository` (Dart 3.10 cấm named param bắt đầu bằng `_`).
- IndexedStack dựng sẵn Profile trên viewport 360px; title/dropdown hồ sơ được nới để không overflow.

Android production không còn fallback History/Dashboard demo khi database lỗi: app hiện màn hình fatal. iOS giữ Demo repository.

V4 native: `libhealthpal_core.so` trên **arm64-v8a** dùng ONNX Runtime (`ort-runtime`). `armeabi-v7a` và `x86_64` dùng cùng trọng số logistic đã export (pyke ORT không có prebuilt cho các ABI đó). Release APK hiện ký bằng debug keystore — không phải production signing.

Kiểm tra trên Android và chụp các màn hình (thay mã thiết bị nếu cần):

```sh
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/auth_flow_test.dart -d emulator-5554
```

Ảnh kiểm tra được lưu tại `build/auth_screenshots/`. Bản APK debug được tạo tại `build/app/outputs/flutter-apk/app-debug.apk`.
