using HealthPal.Application.Abstractions;
using HealthPal.Application.Contracts;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HealthPal.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/profile")]
[Produces("application/json")]
public sealed class ProfileController : ControllerBase
{
    private readonly IProfileService _profiles;
    private readonly ICurrentUser _currentUser;

    public ProfileController(IProfileService profiles, ICurrentUser currentUser)
    {
        _profiles = profiles;
        _currentUser = currentUser;
    }

    [HttpGet]
    [ProducesResponseType(typeof(ProfileDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<ProfileDto>> Get(CancellationToken cancellationToken)
    {
        return Ok(await _profiles.GetAsync(_currentUser.RequireUserId(), cancellationToken));
    }

    [HttpPut]
    [ProducesResponseType(typeof(ProfileDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<ProfileDto>> Update([FromBody] UpdateProfileRequest request, CancellationToken cancellationToken)
    {
        return Ok(await _profiles.UpdateAsync(_currentUser.RequireUserId(), request, cancellationToken));
    }

    [HttpPut("preferences")]
    [ProducesResponseType(typeof(ProfileDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<ProfileDto>> UpdatePreferences([FromBody] UpdatePreferencesRequest request, CancellationToken cancellationToken)
    {
        return Ok(await _profiles.UpdatePreferencesAsync(_currentUser.RequireUserId(), request, cancellationToken));
    }
}
