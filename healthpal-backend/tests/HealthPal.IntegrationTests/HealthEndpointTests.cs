using System.Net;
using FluentAssertions;

namespace HealthPal.IntegrationTests;

[Collection("api")]
public sealed class HealthEndpointTests
{
    private readonly HealthPalApiFactory _factory;

    public HealthEndpointTests(HealthPalApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Live_and_ready_return_200()
    {
        using var client = _factory.CreateClient();
        (await client.GetAsync("/health/live")).StatusCode.Should().Be(HttpStatusCode.OK);
        (await client.GetAsync("/health/ready")).StatusCode.Should().Be(HttpStatusCode.OK);
    }
}
