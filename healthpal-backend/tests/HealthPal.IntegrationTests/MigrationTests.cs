using FluentAssertions;
using HealthPal.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using Testcontainers.PostgreSql;

namespace HealthPal.IntegrationTests;

public sealed class MigrationTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = DockerEndpoint.Postgres("healthpal", "healthpal_migrate").Build();

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
    }

    public async Task DisposeAsync()
    {
        await _postgres.DisposeAsync();
    }

    [Fact]
    public async Task Migrations_can_go_up_and_down_on_real_postgres()
    {
        var options = new DbContextOptionsBuilder<HealthPalDbContext>()
            .UseNpgsql(_postgres.GetConnectionString())
            .UseSnakeCaseNamingConvention()
            .Options;

        await using (var db = new HealthPalDbContext(options))
        {
            await db.Database.MigrateAsync();
            var applied = await db.Database.GetAppliedMigrationsAsync();
            applied.Should().NotBeEmpty();
        }

        await using (var db = new HealthPalDbContext(options))
        {
            var migrator = db.GetService<IMigrator>();
            await migrator.MigrateAsync("0");
            var applied = await db.Database.GetAppliedMigrationsAsync();
            applied.Should().BeEmpty();
        }

        await using (var db = new HealthPalDbContext(options))
        {
            await db.Database.MigrateAsync();
            (await db.Database.CanConnectAsync()).Should().BeTrue();
            var applied = await db.Database.GetAppliedMigrationsAsync();
            applied.Should().NotBeEmpty();
        }
    }
}
