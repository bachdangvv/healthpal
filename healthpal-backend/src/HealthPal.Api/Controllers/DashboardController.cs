using HealthPal.Application.Abstractions;
using HealthPal.Application.Contracts;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HealthPal.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/dashboard")]
[Produces("application/json")]
public sealed class DashboardController : ControllerBase
{
    private readonly IHealthQueryService _queries;
    private readonly ICurrentUser _currentUser;

    public DashboardController(IHealthQueryService queries, ICurrentUser currentUser)
    {
        _queries = queries;
        _currentUser = currentUser;
    }

    [HttpGet("today")]
    [ProducesResponseType(typeof(DashboardTodayDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<DashboardTodayDto>> Today(
        [FromQuery] DateOnly localDate,
        [FromQuery] string? timezone,
        CancellationToken cancellationToken)
    {
        if (localDate == default)
        {
            return ValidationProblem(new ValidationProblemDetails(new Dictionary<string, string[]>
            {
                ["localDate"] = ["localDate is required as YYYY-MM-DD."]
            }));
        }

        return Ok(await _queries.GetDashboardTodayAsync(_currentUser.RequireUserId(), localDate, timezone, cancellationToken));
    }
}
