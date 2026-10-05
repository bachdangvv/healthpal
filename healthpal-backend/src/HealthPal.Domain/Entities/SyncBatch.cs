namespace HealthPal.Domain.Entities;

public sealed class SyncBatch
{
    public Guid Id { get; set; }
    public string UserId { get; set; } = string.Empty;
    public string DeviceId { get; set; } = string.Empty;
    public string IdempotencyKey { get; set; } = string.Empty;
    public int SchemaVersion { get; set; }
    public DateTime GeneratedAtUtc { get; set; }
    public SyncBatchStatus Status { get; set; }
    public string PayloadHash { get; set; } = string.Empty;
    public string ResultJson { get; set; } = "{}";
    public DateTimeOffset CreatedAt { get; set; }
}
