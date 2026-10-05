using HealthPal.Application.Abstractions;
using HealthPal.Application.Contracts;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;

namespace HealthPal.Api.Controllers;

[ApiController]
[Route("api/v1/auth")]
[Produces("application/json")]
public sealed class AuthController : ControllerBase
{
    private readonly IAuthService _auth;
    private readonly ICurrentUser _currentUser;

    public AuthController(IAuthService auth, ICurrentUser currentUser)
    {
        _auth = auth;
        _currentUser = currentUser;
    }

    [HttpPost("register")]
    [AllowAnonymous]
    [EnableRateLimiting("auth")]
    [ProducesResponseType(typeof(AuthSessionDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<AuthSessionDto>> Register([FromBody] RegisterRequest request, CancellationToken cancellationToken)
    {
        return Ok(await _auth.RegisterAsync(request, cancellationToken));
    }

    [HttpPost("login")]
    [AllowAnonymous]
    [EnableRateLimiting("auth")]
    [ProducesResponseType(typeof(AuthSessionDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<AuthSessionDto>> Login([FromBody] LoginRequest request, CancellationToken cancellationToken)
    {
        return Ok(await _auth.LoginAsync(request, cancellationToken));
    }

    [HttpPost("refresh")]
    [AllowAnonymous]
    [EnableRateLimiting("auth")]
    [ProducesResponseType(typeof(TokenPairDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<TokenPairDto>> Refresh([FromBody] RefreshRequest request, CancellationToken cancellationToken)
    {
        return Ok(await _auth.RefreshAsync(request, cancellationToken));
    }

    [HttpPost("logout")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Logout([FromBody] LogoutRequest? request, CancellationToken cancellationToken)
    {
        await _auth.LogoutAsync(_currentUser.RequireUserId(), request ?? new LogoutRequest(), cancellationToken);
        return NoContent();
    }

    [HttpGet("me")]
    [Authorize]
    [ProducesResponseType(typeof(AuthUserDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<AuthUserDto>> Me(CancellationToken cancellationToken)
    {
        return Ok(await _auth.GetMeAsync(_currentUser.RequireUserId(), cancellationToken));
    }

    [HttpPost("change-password")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> ChangePassword([FromBody] ChangePasswordRequest request, CancellationToken cancellationToken)
    {
        await _auth.ChangePasswordAsync(_currentUser.RequireUserId(), request, cancellationToken);
        return NoContent();
    }

    [HttpDelete("account")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> DeleteAccount([FromBody] DeleteAccountRequest request, CancellationToken cancellationToken)
    {
        await _auth.DeleteAccountAsync(_currentUser.RequireUserId(), request, cancellationToken);
        return NoContent();
    }
}
