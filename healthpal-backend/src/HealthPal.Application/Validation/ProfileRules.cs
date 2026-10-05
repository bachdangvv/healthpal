using HealthPal.Application.Contracts;
using HealthPal.Application.Exceptions;
using HealthPal.Domain;
using TimeZoneConverter;

namespace HealthPal.Application.Validation;

public static class ProfileRules
{
    private static readonly HashSet<string> AllowedGoals = new(StringComparer.Ordinal)
    {
        "maintainHealth",
        "loseWeight",
        "buildMuscle",
        "improveFitness"
    };

    public static void ValidateProfile(
        DateOnly? birthDate,
        double? heightCm,
        double? weightKg,
        int? dailyStepGoal,
        string? timezone,
        string? goal,
        DateOnly todayUtc)
    {
        var errors = new Dictionary<string, List<string>>(StringComparer.Ordinal);

        if (birthDate is { } dob && dob > todayUtc)
        {
            Add(errors, "birthDate", "Birth date cannot be in the future.");
        }

        if (heightCm is { } height && (height < HealthPalConstants.MinHeightCm || height > HealthPalConstants.MaxHeightCm))
        {
            Add(errors, "heightCm", $"Height must be between {HealthPalConstants.MinHeightCm} and {HealthPalConstants.MaxHeightCm} cm.");
        }

        if (weightKg is { } weight && (weight < HealthPalConstants.MinWeightKg || weight > HealthPalConstants.MaxWeightKg))
        {
            Add(errors, "weightKg", $"Weight must be between {HealthPalConstants.MinWeightKg} and {HealthPalConstants.MaxWeightKg} kg.");
        }

        if (dailyStepGoal is { } steps && steps < HealthPalConstants.MinDailyStepGoal)
        {
            Add(errors, "dailyStepGoal", $"Daily step goal must be at least {HealthPalConstants.MinDailyStepGoal}.");
        }

        if (!string.IsNullOrWhiteSpace(timezone) && !IsIanaTimezone(timezone))
        {
            Add(errors, "timezone", "Timezone must be a valid IANA identifier.");
        }

        if (!string.IsNullOrWhiteSpace(goal) && !AllowedGoals.Contains(goal))
        {
            Add(errors, "goal", "Goal is not a supported value.");
        }

        ThrowIfAny(errors);
    }

    public static void ValidateUpdate(UpdateProfileRequest request, DateOnly todayUtc)
    {
        if (string.IsNullOrWhiteSpace(request.RowVersion))
        {
            throw new AppValidationException("rowVersion", "Row version is required.");
        }

        ValidateProfile(
            request.BirthDate,
            request.HeightCm,
            request.WeightKg,
            request.DailyStepGoal,
            request.Timezone,
            request.Goal,
            todayUtc);
    }

    public static void ValidatePreferences(UpdatePreferencesRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.RowVersion))
        {
            throw new AppValidationException("rowVersion", "Row version is required.");
        }

        ValidateProfile(
            birthDate: null,
            heightCm: null,
            weightKg: null,
            dailyStepGoal: request.DailyStepGoal,
            timezone: null,
            goal: request.Goal,
            todayUtc: DateOnly.MinValue);
    }

    public static bool TryParseRowVersion(string value, out uint rowVersion)
    {
        return uint.TryParse(value, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out rowVersion);
    }

    public static string FormatRowVersion(uint rowVersion)
    {
        return rowVersion.ToString(System.Globalization.CultureInfo.InvariantCulture);
    }

    private static bool IsIanaTimezone(string timezone)
    {
        try
        {
            _ = TZConvert.GetTimeZoneInfo(timezone);
            return true;
        }
        catch (TimeZoneNotFoundException)
        {
            return false;
        }
        catch (InvalidTimeZoneException)
        {
            return false;
        }
    }

    private static void Add(Dictionary<string, List<string>> errors, string field, string message)
    {
        if (!errors.TryGetValue(field, out var list))
        {
            list = [];
            errors[field] = list;
        }

        list.Add(message);
    }

    private static void ThrowIfAny(Dictionary<string, List<string>> errors)
    {
        if (errors.Count == 0)
        {
            return;
        }

        throw new AppValidationException(errors.ToDictionary(static pair => pair.Key, static pair => pair.Value.ToArray(), StringComparer.Ordinal));
    }
}
