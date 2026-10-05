using HealthPal.Application.Abstractions;
using HealthPal.Application.Contracts;
using HealthPal.Application.Exceptions;
using HealthPal.Application.Validation;
using HealthPal.Infrastructure.Identity;
using HealthPal.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace HealthPal.Infrastructure.Profile;

public sealed class ProfileService : IProfileService
{
    private readonly HealthPalDbContext _db;
    private readonly UserManager<ApplicationUser> _users;
    private readonly IClock _clock;

    public ProfileService(HealthPalDbContext db, UserManager<ApplicationUser> users, IClock clock)
    {
        _db = db;
        _users = users;
        _clock = clock;
    }

    public async Task<ProfileDto> GetAsync(string userId, CancellationToken cancellationToken)
    {
        var user = await _users.FindByIdAsync(userId) ?? throw new UnauthorizedAppException();
        var profile = await _db.UserProfiles.AsNoTracking().SingleOrDefaultAsync(p => p.UserId == userId, cancellationToken)
            ?? throw new NotFoundAppException("Profile not found.");
        return Map(profile, user.Email);
    }

    public async Task<ProfileDto> UpdateAsync(string userId, UpdateProfileRequest request, CancellationToken cancellationToken)
    {
        ProfileRules.ValidateUpdate(request, DateOnly.FromDateTime(_clock.UtcNow.UtcDateTime));
        return await ApplyAsync(
            userId,
            request.RowVersion,
            profile =>
            {
                if (request.DisplayName is not null)
                {
                    profile.DisplayName = request.DisplayName.Trim();
                }

                profile.BirthDate = request.BirthDate;
                profile.Gender = request.Gender;
                profile.HeightCm = request.HeightCm;
                profile.WeightKg = request.WeightKg;
                if (request.Goal is not null)
                {
                    profile.Goal = request.Goal;
                }

                if (request.DailyStepGoal is not null)
                {
                    profile.DailyStepGoal = request.DailyStepGoal.Value;
                }

                profile.Timezone = request.Timezone;
                profile.PreferredSourceId = request.PreferredSourceId;
                if (request.ExperimentalFatigueConsent is not null)
                {
                    profile.ExperimentalFatigueConsent = request.ExperimentalFatigueConsent.Value;
                }
            },
            cancellationToken);
    }

    public async Task<ProfileDto> UpdatePreferencesAsync(string userId, UpdatePreferencesRequest request, CancellationToken cancellationToken)
    {
        ProfileRules.ValidatePreferences(request);
        return await ApplyAsync(
            userId,
            request.RowVersion,
            profile =>
            {
                if (request.Goal is not null)
                {
                    profile.Goal = request.Goal;
                }

                if (request.DailyStepGoal is not null)
                {
                    profile.DailyStepGoal = request.DailyStepGoal.Value;
                }

                if (request.ExperimentalFatigueConsent is not null)
                {
                    profile.ExperimentalFatigueConsent = request.ExperimentalFatigueConsent.Value;
                }

                if (request.PreferredSourceId is not null)
                {
                    profile.PreferredSourceId = request.PreferredSourceId;
                }
            },
            cancellationToken);
    }

    private async Task<ProfileDto> ApplyAsync(
        string userId,
        string rowVersion,
        Action<Domain.Entities.UserProfile> apply,
        CancellationToken cancellationToken)
    {
        if (!ProfileRules.TryParseRowVersion(rowVersion, out var parsed))
        {
            throw new AppValidationException("rowVersion", "Row version is invalid.");
        }

        var user = await _users.FindByIdAsync(userId) ?? throw new UnauthorizedAppException();
        var profile = await _db.UserProfiles.SingleOrDefaultAsync(p => p.UserId == userId, cancellationToken)
            ?? throw new NotFoundAppException("Profile not found.");

        _db.Entry(profile).Property(p => p.RowVersion).OriginalValue = parsed;
        apply(profile);
        profile.UpdatedAt = _clock.UtcNow;

        try
        {
            await _db.SaveChangesAsync(cancellationToken);
        }
        catch (DbUpdateConcurrencyException)
        {
            throw new ConflictAppException("The profile was updated by another request. Reload and retry.", "rowVersion");
        }

        await _db.Entry(profile).ReloadAsync(cancellationToken);
        return Map(profile, user.Email);
    }

    private static ProfileDto Map(Domain.Entities.UserProfile profile, string? email) =>
        new()
        {
            UserId = profile.UserId,
            DisplayName = profile.DisplayName,
            Email = email,
            BirthDate = profile.BirthDate,
            Gender = profile.Gender,
            HeightCm = profile.HeightCm,
            WeightKg = profile.WeightKg,
            Goal = profile.Goal,
            DailyStepGoal = profile.DailyStepGoal,
            Timezone = profile.Timezone,
            PreferredSourceId = profile.PreferredSourceId,
            RowVersion = ProfileRules.FormatRowVersion(profile.RowVersion),
            ExperimentalFatigueConsent = profile.ExperimentalFatigueConsent
        };
}
