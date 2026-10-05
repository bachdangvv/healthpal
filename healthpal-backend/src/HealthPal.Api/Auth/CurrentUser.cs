using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using HealthPal.Application.Abstractions;
using HealthPal.Application.Exceptions;

namespace HealthPal.Api.Auth;

public sealed class CurrentUser : ICurrentUser
{
    private readonly IHttpContextAccessor _httpContextAccessor;

    public CurrentUser(IHttpContextAccessor httpContextAccessor)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    public string? UserId =>
        _httpContextAccessor.HttpContext?.User.FindFirstValue(ClaimTypes.NameIdentifier)
        ?? _httpContextAccessor.HttpContext?.User.FindFirstValue(JwtRegisteredClaimNames.Sub);

    public bool IsAuthenticated =>
        _httpContextAccessor.HttpContext?.User.Identity?.IsAuthenticated == true;

    public string RequireUserId() =>
        UserId ?? throw new UnauthorizedAppException("Authentication is required.");
}
