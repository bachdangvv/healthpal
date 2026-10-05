using System.Net;
using FluentAssertions;
using HealthPal.Application.Contracts;
using HealthPal.Infrastructure.Persistence;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace HealthPal.IntegrationTests;

[Collection("api")]
public sealed class CascadeDeleteTests
{
    private readonly HealthPalApiFactory _factory;

    public CascadeDeleteTests(HealthPalApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Delete_account_requires_password_and_cascades_health_data()
    {
        using var client = _factory.CreateClient();
        var email = $"del-{Guid.NewGuid():N}@healthpal.app";
        var session = await TestJson.RegisterAsync(client, email);
        TestJson.Bearer(client, session.Tokens.AccessToken);

        var batch = SyncFixtures.CreateBatch(
            assessment: SyncFixtures.Assessment(),
            exercise: new ExerciseSessionDto
            {
                ExternalRecordId = "ex-1",
                Type = "yoga",
                StartUtc = new DateTime(2026, 3, 15, 2, 0, 0, DateTimeKind.Utc),
                EndUtc = new DateTime(2026, 3, 15, 3, 0, 0, DateTimeKind.Utc),
                ZoneOffsetMinutes = 0,
                DurationMinutes = 60,
                SourceId = "health_sync"
            });
        (await client.PostAsync("/api/v1/sync/batches", TestJson.Body(batch))).EnsureSuccessStatusCode();

        var wrongPassword = await client.SendAsync(new HttpRequestMessage(HttpMethod.Delete, "/api/v1/auth/account")
        {
            Content = TestJson.Body(new DeleteAccountRequest { Password = "WrongPass1" })
        });
        wrongPassword.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        var deleted = await client.SendAsync(new HttpRequestMessage(HttpMethod.Delete, "/api/v1/auth/account")
        {
            Content = TestJson.Body(new DeleteAccountRequest { Password = "HealthPal123" })
        });
        deleted.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var login = await client.PostAsync(
            "/api/v1/auth/login",
            TestJson.Body(new LoginRequest { Email = email, Password = "HealthPal123" }));
        login.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        await using var scope = _factory.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<HealthPalDbContext>();
        (await db.UserProfiles.CountAsync(p => p.UserId == session.User.Id)).Should().Be(0);
        (await db.HourlyHealthBins.CountAsync(h => h.UserId == session.User.Id)).Should().Be(0);
        (await db.DailyHealthSummaries.CountAsync(d => d.UserId == session.User.Id)).Should().Be(0);
        (await db.ExerciseSessions.CountAsync(e => e.UserId == session.User.Id)).Should().Be(0);
        (await db.FatigueAssessments.CountAsync(a => a.UserId == session.User.Id)).Should().Be(0);
        (await db.SyncBatches.CountAsync(s => s.UserId == session.User.Id)).Should().Be(0);
        (await db.RefreshTokens.CountAsync(t => t.UserId == session.User.Id)).Should().Be(0);
        (await db.Devices.CountAsync(d => d.UserId == session.User.Id)).Should().Be(0);
    }
}
