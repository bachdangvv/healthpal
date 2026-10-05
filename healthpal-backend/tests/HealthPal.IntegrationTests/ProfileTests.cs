using System.Net;
using FluentAssertions;
using HealthPal.Application.Contracts;

namespace HealthPal.IntegrationTests;

[Collection("api")]
public sealed class ProfileTests
{
    private readonly HealthPalApiFactory _factory;

    public ProfileTests(HealthPalApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Get_and_update_profile_round_trip()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client, name: "Minh Anh");
        TestJson.Bearer(client, session.Tokens.AccessToken);

        var profile = await TestJson.Read<ProfileDto>(await client.GetAsync("/api/v1/profile"));
        profile.DisplayName.Should().Be("Minh Anh");
        profile.Email.Should().Be(session.User.Email);
        profile.DailyStepGoal.Should().Be(8000);
        profile.RowVersion.Should().NotBeNullOrWhiteSpace();

        var updated = await client.PutAsync(
            "/api/v1/profile",
            TestJson.Body(new UpdateProfileRequest
            {
                DisplayName = "Minh",
                BirthDate = new DateOnly(1994, 4, 12),
                Gender = "female",
                HeightCm = 162,
                WeightKg = 54,
                Goal = "improveFitness",
                DailyStepGoal = 10000,
                Timezone = "Asia/Ho_Chi_Minh",
                PreferredSourceId = "health_sync",
                ExperimentalFatigueConsent = true,
                RowVersion = profile.RowVersion!
            }));
        updated.StatusCode.Should().Be(HttpStatusCode.OK);
        var after = await TestJson.Read<ProfileDto>(updated);
        after.DisplayName.Should().Be("Minh");
        after.BirthDate.Should().Be(new DateOnly(1994, 4, 12));
        after.Timezone.Should().Be("Asia/Ho_Chi_Minh");
        after.ExperimentalFatigueConsent.Should().BeTrue();
        after.RowVersion.Should().NotBe(profile.RowVersion);

        var me = await TestJson.Read<AuthUserDto>(await client.GetAsync("/api/v1/auth/me"));
        me.Name.Should().Be("Minh");
    }

    [Fact]
    public async Task Validation_rejects_illegal_profile_values()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var profile = await TestJson.Read<ProfileDto>(await client.GetAsync("/api/v1/profile"));

        var futureDob = await client.PutAsync("/api/v1/profile", TestJson.Body(new UpdateProfileRequest
        {
            BirthDate = DateOnly.FromDateTime(DateTime.UtcNow.AddDays(2)),
            RowVersion = profile.RowVersion!
        }));
        futureDob.StatusCode.Should().Be(HttpStatusCode.BadRequest);

        var height = await client.PutAsync("/api/v1/profile", TestJson.Body(new UpdateProfileRequest
        {
            HeightCm = 10,
            RowVersion = profile.RowVersion!
        }));
        height.StatusCode.Should().Be(HttpStatusCode.BadRequest);

        var weight = await client.PutAsync("/api/v1/profile", TestJson.Body(new UpdateProfileRequest
        {
            WeightKg = 500,
            RowVersion = profile.RowVersion!
        }));
        weight.StatusCode.Should().Be(HttpStatusCode.BadRequest);

        var steps = await client.PutAsync("/api/v1/profile/preferences", TestJson.Body(new UpdatePreferencesRequest
        {
            DailyStepGoal = 50,
            RowVersion = profile.RowVersion!
        }));
        steps.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Stale_row_version_returns_409()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var profile = await TestJson.Read<ProfileDto>(await client.GetAsync("/api/v1/profile"));

        var first = await client.PutAsync("/api/v1/profile", TestJson.Body(new UpdateProfileRequest
        {
            DisplayName = "First",
            Timezone = "UTC",
            RowVersion = profile.RowVersion!
        }));
        first.StatusCode.Should().Be(HttpStatusCode.OK);

        var stale = await client.PutAsync("/api/v1/profile", TestJson.Body(new UpdateProfileRequest
        {
            DisplayName = "Stale",
            Timezone = "UTC",
            RowVersion = profile.RowVersion!
        }));
        stale.StatusCode.Should().Be(HttpStatusCode.Conflict);

        var preferences = await client.PutAsync("/api/v1/profile/preferences", TestJson.Body(new UpdatePreferencesRequest
        {
            Goal = "loseWeight",
            DailyStepGoal = 9000,
            ExperimentalFatigueConsent = true,
            RowVersion = profile.RowVersion!
        }));
        preferences.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }
}
