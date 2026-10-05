namespace HealthPal.Application.Abstractions;

public interface ICurrentUser
{
    string? UserId { get; }

    bool IsAuthenticated { get; }

    string RequireUserId();
}
