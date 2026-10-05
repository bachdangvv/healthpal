using HealthPal.Application.Abstractions;
using HealthPal.Application.Contracts;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HealthPal.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/exercises")]
[Produces("application/json")]
public sealed class ExercisesController : ControllerBase
{
    private readonly IHealthQueryService _queries;
    private readonly ICurrentUser _currentUser;

    public ExercisesController(IHealthQueryService queries, ICurrentUser currentUser)
    {
        _queries = queries;
        _currentUser = currentUser;
    }

    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<ExerciseSessionDto>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<ExerciseSessionDto>>> Get(
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

        return Ok(await _queries.GetExercisesAsync(_currentUser.RequireUserId(), from, to, cancellationToken));
    }
}
