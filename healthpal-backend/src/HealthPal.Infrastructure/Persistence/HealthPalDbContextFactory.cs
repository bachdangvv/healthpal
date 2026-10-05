using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace HealthPal.Infrastructure.Persistence;

public sealed class HealthPalDbContextFactory : IDesignTimeDbContextFactory<HealthPalDbContext>
{
    public HealthPalDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<HealthPalDbContext>()
            .UseNpgsql("Host=localhost;Database=healthpal;Username=healthpal;Password=design_time")
            .UseSnakeCaseNamingConvention()
            .Options;
        return new HealthPalDbContext(options);
    }
}
