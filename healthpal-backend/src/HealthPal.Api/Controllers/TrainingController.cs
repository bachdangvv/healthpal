using HealthPal.Application.Abstractions;
using HealthPal.Application.Contracts;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HealthPal.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/training")]
[Produces("application/json")]
public sealed class TrainingController : ControllerBase
{
    private readonly ITrainingService _training;
    private readonly ICurrentUser _currentUser;

    public TrainingController(ITrainingService training, ICurrentUser currentUser)
    {
        _training = training;
        _currentUser = currentUser;
    }

    [HttpGet("readiness")]
    [ProducesResponseType(typeof(TrainingReadinessDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<TrainingReadinessDto>> Readiness(
        [FromQuery] DateOnly localDate,
        CancellationToken cancellationToken)
    {
        if (localDate == default)
            return ValidationProblem(new ValidationProblemDetails(new Dictionary<string, string[]> { ["localDate"] = ["localDate is required as YYYY-MM-DD."] }));
        return Ok(await _training.GetReadinessAsync(_currentUser.RequireUserId(), localDate, cancellationToken));
    }

    [HttpGet("exercises")]
    [ProducesResponseType(typeof(IReadOnlyList<ExerciseCatalogItemDto>), StatusCodes.Status200OK)]
    public async Task<ActionResult<IReadOnlyList<ExerciseCatalogItemDto>>> Exercises(
        [FromQuery] string? muscleGroup,
        [FromQuery] string? query,
        CancellationToken cancellationToken) =>
        Ok(await _training.GetExercisesAsync(_currentUser.RequireUserId(), muscleGroup, query, cancellationToken));

    [HttpPut("exercises/{exerciseId}/favorite")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> SetFavorite(
        string exerciseId,
        [FromBody] SetExerciseFavoriteRequest request,
        CancellationToken cancellationToken)
    {
        try
        {
            await _training.SetFavoriteAsync(_currentUser.RequireUserId(), exerciseId, request.Favorite, cancellationToken);
            return NoContent();
        }
        catch (KeyNotFoundException)
        {
            return NotFound();
        }
    }
}
