using FluentAssertions;
using HealthPal.Application.Contracts;
using HealthPal.Application.Security;

namespace HealthPal.UnitTests;

public sealed class PayloadCanonicalizerTests
{
    [Fact]
    public void Hash_is_stable_for_equivalent_batches()
    {
        var first = Sample();
        var second = Sample();
        PayloadCanonicalizer.Hash(first).Should().Be(PayloadCanonicalizer.Hash(second));
    }

    [Fact]
    public void Hash_changes_when_payload_changes()
    {
        var first = Sample();
        var second = Sample();
        second.HourlyBins[0].Steps = 9;
        PayloadCanonicalizer.Hash(first).Should().NotBe(PayloadCanonicalizer.Hash(second));
    }

    private static SyncBatchDto Sample() =>
        new()
        {
            SchemaVersion = 1,
            DeviceId = "device-1",
            IdempotencyKey = "key-1",
            GeneratedAtUtc = new DateTime(2026, 3, 15, 12, 0, 0, DateTimeKind.Utc),
            HourlyBins =
            [
                new HourlyHealthBinDto
                {
                    HourUtc = new DateTime(2026, 3, 15, 11, 0, 0, DateTimeKind.Utc),
                    ZoneOffsetMinutes = 420,
                    Steps = 100,
                    SourceId = "health_sync"
                }
            ]
        };
}
