using HealthPal.Application.Abstractions;
using HealthPal.Infrastructure.Auth;
using HealthPal.Infrastructure.Identity;
using HealthPal.Infrastructure.Persistence;
using HealthPal.Infrastructure.Profile;
using HealthPal.Infrastructure.Query;
using HealthPal.Infrastructure.Sync;
using HealthPal.Infrastructure.Time;
using HealthPal.Infrastructure.Training;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace HealthPal.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddHealthPalInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<JwtOptions>(configuration.GetSection(JwtOptions.SectionName));
        services.AddSingleton<IClock, SystemClock>();
        services.AddScoped<JwtTokenService>();
        services.AddScoped<HealthUpsertExecutor>();
        services.AddScoped<IAuthService, AuthService>();
        services.AddScoped<IProfileService, ProfileService>();
        services.AddScoped<ISyncService, SyncService>();
        services.AddScoped<IHealthQueryService, HealthQueryService>();
        services.AddScoped<ITrainingService, TrainingService>();

        services.AddDbContext<HealthPalDbContext>((provider, options) =>
        {
            var resolved = PostgresConnection.Resolve(provider.GetRequiredService<IConfiguration>());
            options.UseNpgsql(resolved);
            options.UseSnakeCaseNamingConvention();
        });

        services
            .AddIdentityCore<ApplicationUser>(options =>
            {
                options.Password.RequiredLength = 8;
                options.Password.RequireDigit = true;
                options.Password.RequireUppercase = true;
                options.Password.RequireLowercase = true;
                options.Password.RequireNonAlphanumeric = false;
                options.User.RequireUniqueEmail = true;
                options.Lockout.AllowedForNewUsers = false;
            })
            .AddEntityFrameworkStores<HealthPalDbContext>();

        return services;
    }
}
