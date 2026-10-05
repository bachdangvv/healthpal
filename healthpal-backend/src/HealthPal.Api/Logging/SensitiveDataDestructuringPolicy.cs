using Serilog.Core;
using Serilog.Events;

namespace HealthPal.Api.Logging;

public sealed class SensitiveDataDestructuringPolicy : IDestructuringPolicy
{
    private static readonly HashSet<string> SensitiveNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "password",
        "currentPassword",
        "newPassword",
        "refreshToken",
        "accessToken",
        "token",
        "authorization",
        "signingKey",
        "featureVectorJson",
        "hourlyBins",
        "dailySummaries",
        "exerciseSessions",
        "fatigueAssessments"
    };

    public bool TryDestructure(object value, ILogEventPropertyValueFactory propertyValueFactory, out LogEventPropertyValue result)
    {
        if (value is IDictionary<string, object?> dictionary)
        {
            var properties = new List<LogEventProperty>();
            foreach (var pair in dictionary)
            {
                var rendered = SensitiveNames.Contains(pair.Key)
                    ? new ScalarValue("[REDACTED]")
                    : propertyValueFactory.CreatePropertyValue(pair.Value, true);
                properties.Add(new LogEventProperty(pair.Key, rendered));
            }

            result = new StructureValue(properties);
            return true;
        }

        result = new ScalarValue(null);
        return false;
    }
}
