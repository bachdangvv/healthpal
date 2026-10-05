using HealthPal.Application.Contracts;

namespace HealthPal.Application.Abstractions;

public interface ISyncService
{
    Task<SyncBatchResultDto> IngestAsync(string userId, SyncBatchDto batch, CancellationToken cancellationToken);
}
