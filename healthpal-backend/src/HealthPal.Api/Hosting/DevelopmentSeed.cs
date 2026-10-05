using HealthPal.Domain;
using HealthPal.Domain.Entities;
using HealthPal.Infrastructure.Identity;
using HealthPal.Infrastructure.Persistence;
using Microsoft.AspNetCore.Identity;

namespace HealthPal.Api.Hosting;

public static class DevelopmentSeed
{
    public const string DemoEmail = "demo@healthpal.app";
    public const string DemoPassword = "HealthPal123";
    public const string DemoName = "Minh Anh";

    public static async Task SeedAsync(IServiceProvider services, CancellationToken cancellationToken)
    {
        using var scope = services.CreateScope();
        var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
        var db = scope.ServiceProvider.GetRequiredService<HealthPalDbContext>();
        if (await users.FindByEmailAsync(DemoEmail) is not null)
        {
            return;
        }

        var user = new ApplicationUser
        {
            UserName = DemoEmail,
            Email = DemoEmail,
            EmailConfirmed = true
        };
        var created = await users.CreateAsync(user, DemoPassword);
        if (!created.Succeeded)
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        db.UserProfiles.Add(new UserProfile
        {
            UserId = user.Id,
            DisplayName = DemoName,
            DailyStepGoal = HealthPalConstants.DefaultDailyStepGoal,
            Timezone = "UTC",
            CreatedAt = now,
            UpdatedAt = now
        });
        await db.SaveChangesAsync(cancellationToken);
    }
}
