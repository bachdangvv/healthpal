using HealthPal.Application.Contracts;

namespace HealthPal.Application.Abstractions;

public interface IAuthService
{
    Task<AuthSessionDto> RegisterAsync(RegisterRequest request, CancellationToken cancellationToken);

    Task<AuthSessionDto> LoginAsync(LoginRequest request, CancellationToken cancellationToken);

    Task<TokenPairDto> RefreshAsync(RefreshRequest request, CancellationToken cancellationToken);

    Task LogoutAsync(string userId, LogoutRequest request, CancellationToken cancellationToken);

    Task<AuthUserDto> GetMeAsync(string userId, CancellationToken cancellationToken);

    Task ChangePasswordAsync(string userId, ChangePasswordRequest request, CancellationToken cancellationToken);

    Task DeleteAccountAsync(string userId, DeleteAccountRequest request, CancellationToken cancellationToken);
}
