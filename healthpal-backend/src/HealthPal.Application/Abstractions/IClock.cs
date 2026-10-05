namespace HealthPal.Application.Abstractions;

public interface IClock
{
    DateTimeOffset UtcNow { get; }
}
