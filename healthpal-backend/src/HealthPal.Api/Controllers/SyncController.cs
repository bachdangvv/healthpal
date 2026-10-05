using HealthPal.Application.Abstractions;
using HealthPal.Application.Contracts;
using HealthPal.Domain;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace HealthPal.Api.Controllers;

[ApiController]
[Authorize]
[Route("api/v1/sync")]
[Produces("application/json")]
public sealed class SyncController : ControllerBase
{
    private readonly ISyncService _sync;
    private readonly ICurrentUser _currentUser;

    public SyncController(ISyncService sync, ICurrentUser currentUser)
    {
        _sync = sync;
        _currentUser = currentUser;
    }

    [HttpPost("batches")]
    [RequestSizeLimit(HealthPalConstants.MaxSyncPayloadBytes)]
    [RequestFormLimits(MultipartBodyLengthLimit = HealthPalConstants.MaxSyncPayloadBytes)]
    [ProducesResponseType(typeof(SyncBatchResultDto), StatusCodes.Status200OK)]
    public async Task<ActionResult<SyncBatchResultDto>> Ingest([FromBody] SyncBatchDto batch, CancellationToken cancellationToken)
    {
        return Ok(await _sync.IngestAsync(_currentUser.RequireUserId(), batch, cancellationToken));
    }
}
