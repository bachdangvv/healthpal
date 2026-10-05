using HealthPal.Application.Abstractions;
using HealthPal.Application.Contracts;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HealthPal.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/history")]
[Produces("application/json")]
public sealed class HistoryController : ControllerBase
{
    private readonly IHealthQueryService _queries;
    private readonly ICurrentUser _currentUser;

    public HistoryController(IHealthQueryService queries, ICurrentUser currentUser)
    {
        _queries = queries;
        _currentUser = currentUser;
    }

    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<DailyHealthSummaryDto>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<DailyHealthSummaryDto>>> Get(
        [FromQuery] DateOnly from,
        [FromQuery] DateOnly to,
        CancellationToken cancellationToken)
    {
        if (from == default || to == default)
        {
            return ValidationProblem(new ValidationProblemDetails(new Dictionary<string, string[]>
            {
                ["from"] = ["from and to are required as YYYY-MM-DD."]
            }));
        }

        return Ok(await _queries.GetHistoryAsync(_currentUser.RequireUserId(), from, to, cancellationToken));
    }
}
