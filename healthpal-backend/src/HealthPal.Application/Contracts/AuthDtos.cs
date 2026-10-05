using System.ComponentModel.DataAnnotations;

namespace HealthPal.Application.Contracts;

public sealed class AuthUserDto
{
    public required string Id { get; init; }
    public required string Name { get; init; }
    public required string Email { get; init; }
}

public sealed class TokenPairDto
{
    public required string AccessToken { get; init; }
    public required string RefreshToken { get; init; }
    public required DateTime AccessExpiresAtUtc { get; init; }
    public required DateTime RefreshExpiresAtUtc { get; init; }
}

public sealed class AuthSessionDto
{
    public required AuthUserDto User { get; init; }
    public required TokenPairDto Tokens { get; init; }
}

public sealed class RegisterRequest
{
    [Required]
    [StringLength(100, MinimumLength = 1)]
    public string Name { get; set; } = string.Empty;

    [Required]
    [EmailAddress]
    [StringLength(256)]
    public string Email { get; set; } = string.Empty;

    [Required]
    [StringLength(128, MinimumLength = 8)]
    public string Password { get; set; } = string.Empty;

    [StringLength(128)]
    public string? DeviceId { get; set; }
}

public sealed class LoginRequest
{
    [Required]
    [EmailAddress]
    [StringLength(256)]
    public string Email { get; set; } = string.Empty;

    [Required]
    [StringLength(128)]
    public string Password { get; set; } = string.Empty;

    [StringLength(128)]
    public string? DeviceId { get; set; }
}

public sealed class RefreshRequest
{
    [Required]
    public string RefreshToken { get; set; } = string.Empty;
}

public sealed class LogoutRequest
{
    public string? RefreshToken { get; set; }
}

public sealed class ChangePasswordRequest
{
    [Required]
    public string CurrentPassword { get; set; } = string.Empty;

    [Required]
    [StringLength(128, MinimumLength = 8)]
    public string NewPassword { get; set; } = string.Empty;
}

public sealed class DeleteAccountRequest
{
    [Required]
    public string Password { get; set; } = string.Empty;
}
