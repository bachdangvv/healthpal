using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Testcontainers.PostgreSql;

namespace HealthPal.IntegrationTests;

public sealed class HealthPalApiFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = DockerEndpoint.Postgres("healthpal", "healthpal_test").Build();

    public string ConnectionString => _postgres.GetConnectionString();

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
    }

    async Task IAsyncLifetime.DisposeAsync()
    {
        await _postgres.DisposeAsync();
        await DisposeAsync();
    }

    private IReadOnlyDictionary<string, string?> TestSettings() =>
        new Dictionary<string, string?>
        {
            ["ConnectionStrings:DefaultConnection"] = _postgres.GetConnectionString(),
            ["POSTGRES_PASSWORD"] = string.Empty,
            ["Jwt:Issuer"] = "HealthPal",
            ["Jwt:Audience"] = "HealthPal.Mobile",
            ["Jwt:SigningKey"] = "test-signing-key-must-be-at-least-32-bytes!",
            ["Jwt:AccessTokenMinutes"] = "15",
            ["Jwt:RefreshTokenDays"] = "30"
        };

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        foreach (var pair in TestSettings())
        {
            if (pair.Value is not null)
            {
                builder.UseSetting(pair.Key, pair.Value);
            }
        }

        builder.ConfigureAppConfiguration((_, config) => config.AddInMemoryCollection(TestSettings()));
    }

    protected override IHost CreateHost(IHostBuilder builder)
    {
        builder.ConfigureHostConfiguration(config => config.AddInMemoryCollection(TestSettings()));
        return base.CreateHost(builder);
    }
}

[CollectionDefinition("api")]
public sealed class ApiCollection : ICollectionFixture<HealthPalApiFactory>
{
}
