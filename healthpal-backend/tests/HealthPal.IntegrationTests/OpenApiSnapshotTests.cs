using System.Text.Json;
using System.Text.Json.Nodes;
using FluentAssertions;

namespace HealthPal.IntegrationTests;

[Collection("api")]
public sealed class OpenApiSnapshotTests
{
    private readonly HealthPalApiFactory _factory;

    public OpenApiSnapshotTests(HealthPalApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task OpenApi_snapshot_matches_committed_contract()
    {
        using var client = _factory.CreateClient();
        var response = await client.GetAsync("/swagger/v1/swagger.json");
        response.EnsureSuccessStatusCode();
        var current = await response.Content.ReadAsStringAsync();

        var snapshotPath = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "openapi", "healthpal-v1.json"));
        Directory.CreateDirectory(Path.GetDirectoryName(snapshotPath)!);
        if (!File.Exists(snapshotPath) || string.Equals(Environment.GetEnvironmentVariable("UPDATE_OPENAPI"), "1", StringComparison.Ordinal))
        {
            await File.WriteAllTextAsync(snapshotPath, Canonical(current));
        }

        var committed = await File.ReadAllTextAsync(snapshotPath);
        Canonical(current).Should().Be(Canonical(committed));
        committed.Should().Contain("/api/v1/auth/register");
        committed.Should().Contain("/api/v1/sync/batches");
        committed.Should().Contain("/api/v1/dashboard/today");
    }

    private static string Canonical(string json)
    {
        var node = JsonNode.Parse(json) ?? throw new InvalidOperationException("OpenAPI JSON is empty.");
        return node.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }
}
