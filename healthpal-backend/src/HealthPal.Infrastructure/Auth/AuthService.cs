using HealthPal.Application.Abstractions;
using HealthPal.Application.Contracts;
using HealthPal.Application.Exceptions;
using HealthPal.Application.Security;
using HealthPal.Domain;
using HealthPal.Domain.Entities;
using HealthPal.Infrastructure.Identity;
using HealthPal.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace HealthPal.Infrastructure.Auth;

public sealed class AuthService : IAuthService
{
    private static readonly string DummyPasswordHash =
        new PasswordHasher<ApplicationUser>().HashPassword(new ApplicationUser(), "not-a-real-password");

    private readonly UserManager<ApplicationUser> _users;
    private readonly HealthPalDbContext _db;
    private readonly JwtTokenService _tokens;
    private readonly JwtOptions _jwt;
    private readonly IClock _clock;
    private readonly IPasswordHasher<ApplicationUser> _passwordHasher;
    private readonly ILogger<AuthService> _logger;

    public AuthService(
        UserManager<ApplicationUser> users,
        HealthPalDbContext db,
        JwtTokenService tokens,
        IOptions<JwtOptions> jwt,
        IClock clock,
        IPasswordHasher<ApplicationUser> passwordHasher,
        ILogger<AuthService> logger)
    {
        _users = users;
        _db = db;
        _tokens = tokens;
        _jwt = jwt.Value;
        _clock = clock;
        _passwordHasher = passwordHasher;
        _logger = logger;
    }

    public async Task<AuthSessionDto> RegisterAsync(RegisterRequest request, CancellationToken cancellationToken)
    {
        var email = NormalizeEmail(request.Email);
        var name = request.Name.Trim();
        if (string.IsNullOrWhiteSpace(name))
        {
            throw new AppValidationException("name", "Name is required.");
        }

        if (await _users.FindByEmailAsync(email) is not null)
        {
            throw new ConflictAppException("Email is already registered.", "email");
        }

        var user = new ApplicationUser
        {
            UserName = email,
            Email = email,
            EmailConfirmed = true
        };

        var created = await _users.CreateAsync(user, request.Password);
        if (!created.Succeeded)
        {
            throw MapIdentityErrors(created, "password");
        }

        var now = _clock.UtcNow;
        _db.UserProfiles.Add(new UserProfile
        {
            UserId = user.Id,
            DisplayName = name,
            DailyStepGoal = HealthPalConstants.DefaultDailyStepGoal,
            Timezone = "UTC",
            CreatedAt = now,
            UpdatedAt = now
        });
        await _db.SaveChangesAsync(cancellationToken);
        return await IssueSessionAsync(user, request.DeviceId, cancellationToken);
    }

    public async Task<AuthSessionDto> LoginAsync(LoginRequest request, CancellationToken cancellationToken)
    {
        var email = NormalizeEmail(request.Email);
        var user = await _users.FindByEmailAsync(email);
        if (user is null)
        {
            _passwordHasher.VerifyHashedPassword(new ApplicationUser(), DummyPasswordHash, request.Password);
            throw new UnauthorizedAppException();
        }

        if (!await _users.CheckPasswordAsync(user, request.Password))
        {
            throw new UnauthorizedAppException();
        }

        return await IssueSessionAsync(user, request.DeviceId, cancellationToken);
    }

    public async Task<TokenPairDto> RefreshAsync(RefreshRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.RefreshToken))
        {
            throw new UnauthorizedAppException();
        }

        var hash = TokenHash.Sha256Hex(request.RefreshToken);
        var stored = await _db.RefreshTokens.FirstOrDefaultAsync(t => t.TokenHash == hash, cancellationToken);
        if (stored is null)
        {
            throw new UnauthorizedAppException();
        }

        if (stored.RevokedAt is not null)
        {
            if (stored.ReplacedByTokenHash is not null)
            {
                await RevokeFamilyAsync(stored.FamilyId, cancellationToken);
                await _db.SaveChangesAsync(cancellationToken);
                _logger.LogWarning("Refresh token reuse detected for family {FamilyId}", stored.FamilyId);
            }

            throw new UnauthorizedAppException();
        }

        if (stored.ExpiresAt <= _clock.UtcNow)
        {
            throw new UnauthorizedAppException();
        }

        var user = await _users.FindByIdAsync(stored.UserId);
        if (user is null)
        {
            throw new UnauthorizedAppException();
        }

        var profile = await _db.UserProfiles.SingleAsync(p => p.UserId == user.Id, cancellationToken);
        return await RotateAsync(user, profile.DisplayName, stored, cancellationToken);
    }

    public async Task LogoutAsync(string userId, LogoutRequest request, CancellationToken cancellationToken)
    {
        if (!string.IsNullOrWhiteSpace(request.RefreshToken))
        {
            var hash = TokenHash.Sha256Hex(request.RefreshToken);
            var stored = await _db.RefreshTokens.FirstOrDefaultAsync(
                t => t.TokenHash == hash && t.UserId == userId,
                cancellationToken);
            if (stored is not null)
            {
                await RevokeFamilyAsync(stored.FamilyId, cancellationToken);
                await _db.SaveChangesAsync(cancellationToken);
                return;
            }
        }

        var tokens = await _db.RefreshTokens.Where(t => t.UserId == userId && t.RevokedAt == null).ToListAsync(cancellationToken);
        var now = _clock.UtcNow;
        foreach (var token in tokens)
        {
            token.RevokedAt = now;
        }

        await _db.SaveChangesAsync(cancellationToken);
    }

    public async Task<AuthUserDto> GetMeAsync(string userId, CancellationToken cancellationToken)
    {
        var user = await _users.FindByIdAsync(userId) ?? throw new UnauthorizedAppException();
        var profile = await _db.UserProfiles.AsNoTracking().SingleAsync(p => p.UserId == userId, cancellationToken);
        return new AuthUserDto
        {
            Id = user.Id,
            Name = profile.DisplayName,
            Email = user.Email ?? string.Empty
        };
    }

    public async Task ChangePasswordAsync(string userId, ChangePasswordRequest request, CancellationToken cancellationToken)
    {
        var user = await _users.FindByIdAsync(userId) ?? throw new UnauthorizedAppException();
        var result = await _users.ChangePasswordAsync(user, request.CurrentPassword, request.NewPassword);
        if (!result.Succeeded)
        {
            if (result.Errors.Any(e => e.Code is "PasswordMismatch"))
            {
                throw new UnauthorizedAppException();
            }

            throw MapIdentityErrors(result, "newPassword");
        }

        var now = _clock.UtcNow;
        var tokens = await _db.RefreshTokens.Where(t => t.UserId == userId && t.RevokedAt == null).ToListAsync(cancellationToken);
        foreach (var token in tokens)
        {
            token.RevokedAt = now;
        }

        await _db.SaveChangesAsync(cancellationToken);
    }

    public async Task DeleteAccountAsync(string userId, DeleteAccountRequest request, CancellationToken cancellationToken)
    {
        var user = await _users.FindByIdAsync(userId) ?? throw new UnauthorizedAppException();
        if (!await _users.CheckPasswordAsync(user, request.Password))
        {
            throw new UnauthorizedAppException();
        }

        var result = await _users.DeleteAsync(user);
        if (!result.Succeeded)
        {
            throw new AppValidationException("account", "Unable to delete account.");
        }
    }

    private async Task<AuthSessionDto> IssueSessionAsync(ApplicationUser user, string? deviceId, CancellationToken cancellationToken)
    {
        var profile = await _db.UserProfiles.SingleAsync(p => p.UserId == user.Id, cancellationToken);
        var tokens = await CreateTokenPairAsync(user, profile.DisplayName, deviceId ?? string.Empty, Guid.NewGuid(), cancellationToken);
        return new AuthSessionDto
        {
            User = new AuthUserDto
            {
                Id = user.Id,
                Name = profile.DisplayName,
                Email = user.Email ?? string.Empty
            },
            Tokens = tokens
        };
    }

    private async Task<TokenPairDto> RotateAsync(
        ApplicationUser user,
        string displayName,
        RefreshToken current,
        CancellationToken cancellationToken)
    {
        var pair = await CreateTokenPairAsync(user, displayName, current.DeviceId, current.FamilyId, cancellationToken);
        current.RevokedAt = _clock.UtcNow;
        current.ReplacedByTokenHash = TokenHash.Sha256Hex(pair.RefreshToken);
        await _db.SaveChangesAsync(cancellationToken);
        return pair;
    }

    private async Task<TokenPairDto> CreateTokenPairAsync(
        ApplicationUser user,
        string displayName,
        string deviceId,
        Guid familyId,
        CancellationToken cancellationToken)
    {
        var now = _clock.UtcNow;
        var accessExpires = now.AddMinutes(_jwt.AccessTokenMinutes);
        var refreshExpires = now.AddDays(_jwt.RefreshTokenDays);
        var refresh = TokenHash.CreateRefreshToken();
        _db.RefreshTokens.Add(new RefreshToken
        {
            Id = Guid.NewGuid(),
            TokenHash = TokenHash.Sha256Hex(refresh),
            UserId = user.Id,
            DeviceId = deviceId,
            FamilyId = familyId,
            ExpiresAt = refreshExpires,
            CreatedAt = now
        });
        await _db.SaveChangesAsync(cancellationToken);

        return new TokenPairDto
        {
            AccessToken = _tokens.CreateAccessToken(user, displayName, accessExpires),
            RefreshToken = refresh,
            AccessExpiresAtUtc = accessExpires.UtcDateTime,
            RefreshExpiresAtUtc = refreshExpires.UtcDateTime
        };
    }

    private async Task RevokeFamilyAsync(Guid familyId, CancellationToken cancellationToken)
    {
        var now = _clock.UtcNow;
        var tokens = await _db.RefreshTokens
            .Where(t => t.FamilyId == familyId && t.RevokedAt == null)
            .ToListAsync(cancellationToken);
        foreach (var token in tokens)
        {
            token.RevokedAt = now;
        }
    }

    private static string NormalizeEmail(string email) => email.Trim().ToLowerInvariant();

    private static AppValidationException MapIdentityErrors(IdentityResult result, string fallbackField)
    {
        var errors = new Dictionary<string, List<string>>(StringComparer.Ordinal);
        foreach (var error in result.Errors)
        {
            var field = error.Code.Contains("Password", StringComparison.OrdinalIgnoreCase)
                ? fallbackField
                : error.Code.Contains("Email", StringComparison.OrdinalIgnoreCase)
                    ? "email"
                    : fallbackField;
            if (!errors.TryGetValue(field, out var list))
            {
                list = [];
                errors[field] = list;
            }

            list.Add(error.Description);
        }

        if (errors.Count == 0)
        {
            errors[fallbackField] = ["The request is invalid."];
        }

        return new AppValidationException(errors.ToDictionary(static pair => pair.Key, static pair => pair.Value.ToArray(), StringComparer.Ordinal));
    }
}
