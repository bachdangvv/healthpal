using HealthPal.Application.Contracts;

namespace HealthPal.Application.Abstractions;

public interface IProfileService
{
    Task<ProfileDto> GetAsync(string userId, CancellationToken cancellationToken);

    Task<ProfileDto> UpdateAsync(string userId, UpdateProfileRequest request, CancellationToken cancellationToken);

    Task<ProfileDto> UpdatePreferencesAsync(string userId, UpdatePreferencesRequest request, CancellationToken cancellationToken);
}
