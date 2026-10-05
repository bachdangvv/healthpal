using System.Net;
using FluentAssertions;
using HealthPal.Application.Contracts;

namespace HealthPal.IntegrationTests;

[Collection("api")]
public sealed class AuthorizationIsolationTests
{
    private readonly HealthPalApiFactory _factory;

    public AuthorizationIsolationTests(HealthPalApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task User_A_cannot_read_or_update_user_B()
    {
        using var client = _factory.CreateClient();
        var userA = await TestJson.RegisterAsync(client, name: "User A");
        var userB = await TestJson.RegisterAsync(client, name: "User B");

        TestJson.Bearer(client, userB.Tokens.AccessToken);
        var bProfile = await TestJson.Read<ProfileDto>(await client.GetAsync("/api/v1/profile"));
        var updateB = await client.PutAsync(
            "/api/v1/profile",
            TestJson.Body(new UpdateProfileRequest
            {
                DisplayName = "User B Updated",
                Timezone = "UTC",
                RowVersion = bProfile.RowVersion!
            }));
        updateB.EnsureSuccessStatusCode();

        var batch = SyncFixtures.CreateBatch(
            deviceId: "device-b",
            localDate: new DateOnly(2026, 3, 15),
            steps: 1234);
        var sync = await client.PostAsync("/api/v1/sync/batches", TestJson.Body(batch));
        sync.EnsureSuccessStatusCode();

        TestJson.Bearer(client, userA.Tokens.AccessToken);
        var aProfile = await TestJson.Read<ProfileDto>(await client.GetAsync("/api/v1/profile"));
        aProfile.DisplayName.Should().Be("User A");
        aProfile.UserId.Should().Be(userA.User.Id);

        var history = await TestJson.Read<List<DailyHealthSummaryDto>>(
            await client.GetAsync("/api/v1/history?from=2026-03-15&to=2026-03-15"));
        history.Should().BeEmpty();

        var dashboard = await TestJson.Read<DashboardTodayDto>(
            await client.GetAsync("/api/v1/dashboard/today?localDate=2026-03-15&timezone=UTC"));
        dashboard.Summary.Should().BeNull();

        var stolenUpdate = await client.PutAsync(
            "/api/v1/profile",
            TestJson.Body(new UpdateProfileRequest
            {
                DisplayName = "Hijacked",
                RowVersion = bProfile.RowVersion!
            }));
        stolenUpdate.StatusCode.Should().BeOneOf(HttpStatusCode.Conflict, HttpStatusCode.OK);
        if (stolenUpdate.StatusCode == HttpStatusCode.OK)
        {
            var updatedA = await TestJson.Read<ProfileDto>(stolenUpdate);
            updatedA.UserId.Should().Be(userA.User.Id);
        }

        TestJson.Bearer(client, userB.Tokens.AccessToken);
        var bAfter = await TestJson.Read<ProfileDto>(await client.GetAsync("/api/v1/profile"));
        bAfter.DisplayName.Should().Be("User B Updated");
        bAfter.UserId.Should().Be(userB.User.Id);
    }
}
