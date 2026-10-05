namespace HealthPal.Domain.Entities;

public sealed class Device
{
    public string UserId { get; set; } = string.Empty;
    public string Id { get; set; } = string.Empty;
    public string Platform { get; set; } = "android";
    public string? AppVersion { get; set; }
    public string? ModelVersion { get; set; }
    public string? SourcePreference { get; set; }
    public DateTimeOffset LastSeenAt { get; set; }
}
