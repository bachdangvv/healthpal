using FluentAssertions;
using HealthPal.Application.Contracts;
using HealthPal.Application.Exceptions;
using HealthPal.Application.Validation;

namespace HealthPal.UnitTests;

public sealed class ProfileRulesTests
{
    private static readonly DateOnly Today = new(2026, 3, 15);

    [Fact]
    public void Rejects_future_birth_date()
    {
        var act = () => ProfileRules.ValidateProfile(Today.AddDays(1), 170, 65, 8000, "UTC", "maintainHealth", Today);
        act.Should().Throw<AppValidationException>().Which.Errors.Should().ContainKey("birthDate");
    }

    [Theory]
    [InlineData(49)]
    [InlineData(251)]
    public void Rejects_height_out_of_range(double height)
    {
        var act = () => ProfileRules.ValidateProfile(null, height, 65, 8000, "UTC", null, Today);
        act.Should().Throw<AppValidationException>().Which.Errors.Should().ContainKey("heightCm");
    }

    [Theory]
    [InlineData(19)]
    [InlineData(401)]
    public void Rejects_weight_out_of_range(double weight)
    {
        var act = () => ProfileRules.ValidateProfile(null, 170, weight, 8000, "UTC", null, Today);
        act.Should().Throw<AppValidationException>().Which.Errors.Should().ContainKey("weightKg");
    }

    [Fact]
    public void Rejects_step_goal_below_100()
    {
        var act = () => ProfileRules.ValidateProfile(null, null, null, 99, null, null, Today);
        act.Should().Throw<AppValidationException>().Which.Errors.Should().ContainKey("dailyStepGoal");
    }

    [Fact]
    public void Rejects_invalid_timezone()
    {
        var act = () => ProfileRules.ValidateProfile(null, null, null, 1000, "Not/A_Zone", null, Today);
        act.Should().Throw<AppValidationException>().Which.Errors.Should().ContainKey("timezone");
    }

    [Fact]
    public void Accepts_iana_timezone_and_bounds()
    {
        var act = () => ProfileRules.ValidateProfile(
            new DateOnly(1994, 4, 12),
            50,
            20,
            100,
            "Asia/Ho_Chi_Minh",
            "loseWeight",
            Today);
        act.Should().NotThrow();
    }

    [Fact]
    public void Preferences_require_row_version()
    {
        var act = () => ProfileRules.ValidatePreferences(new UpdatePreferencesRequest { RowVersion = " " });
        act.Should().Throw<AppValidationException>().Which.Errors.Should().ContainKey("rowVersion");
    }
}
