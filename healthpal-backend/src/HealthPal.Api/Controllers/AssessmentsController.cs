using HealthPal.Application.Abstractions;
using HealthPal.Application.Contracts;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HealthPal.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/assessments")]
[Produces("application/json")]
public sealed class AssessmentsController : ControllerBase
{
    private readonly IHealthQueryService _queries;
    private readonly ICurrentUser _currentUser;

    public AssessmentsController(IHealthQueryService queries, ICurrentUser currentUser)
    {
        _queries = queries;
        _currentUser = currentUser;
    }

    [HttpGet("latest")]
    [ProducesResponseType(typeof(FatigueAssessmentDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<FatigueAssessmentDto>> Latest(CancellationToken cancellationToken)
    {
        var assessment = await _queries.GetLatestAssessmentAsync(_currentUser.RequireUserId(), cancellationToken);
        if (assessment is null)
        {
            return NotFound();
        }

        return Ok(assessment);
    }
}
