import '../../../core/sync/sync_state.dart';

enum HealthSourceFreshness { connectedFresh, connectedStale, needsSourceSync }

HealthSourceFreshness freshnessFor({
  required SyncState state,
  required DateTime nowUtc,
  Duration staleAfter = const Duration(hours: 2),
}) {
  final latest = state.latestDataAtUtc;
  final synced = state.lastSuccessfulSyncAtUtc;
  if (latest == null) return HealthSourceFreshness.needsSourceSync;
  if (nowUtc.difference(latest) > staleAfter) {
    if (synced != null && synced.isAfter(latest)) {
      return HealthSourceFreshness.needsSourceSync;
    }
    return HealthSourceFreshness.connectedStale;
  }
  return HealthSourceFreshness.connectedFresh;
}

const huaweiSyncHelp =
    'Mở Health Sync, bật Daily Sync, đồng bộ Huawei Health, rồi quay lại HealthPal và bấm Đồng bộ ngay. HealthPal đọc Health Connect; nó không thể ép Health Sync chạy.';
