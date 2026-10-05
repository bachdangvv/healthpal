using System.IdentityModel.Tokens.Jwt;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.RateLimiting;
using HealthPal.Api.Auth;
using HealthPal.Api.Hosting;
using HealthPal.Api.Logging;
using HealthPal.Api.Middleware;
using HealthPal.Api.Serialization;
using HealthPal.Application.Abstractions;
using HealthPal.Domain;
using HealthPal.Infrastructure;
using HealthPal.Infrastructure.Auth;
using HealthPal.Infrastructure.Persistence;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using Serilog;
using Serilog.Formatting.Compact;
using System.Security.Claims;
using System.Text;

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console(new RenderedCompactJsonFormatter())
    .CreateBootstrapLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);
    if (!builder.Environment.IsEnvironment("Testing"))
    {
        builder.WebHost.ConfigureKestrel(options =>
        {
            options.ListenAnyIP(5080);
            options.Limits.MaxRequestBodySize = HealthPalConstants.MaxSyncPayloadBytes;
        });
    }
    else
    {
        builder.WebHost.ConfigureKestrel(options =>
        {
            options.Limits.MaxRequestBodySize = HealthPalConstants.MaxSyncPayloadBytes;
        });
    }

    builder.Host.UseSerilog((context, services, logger) =>
    {
        logger
            .ReadFrom.Configuration(context.Configuration)
            .ReadFrom.Services(services)
            .Enrich.FromLogContext()
            .Destructure.With<SensitiveDataDestructuringPolicy>()
            .WriteTo.Console(new RenderedCompactJsonFormatter());
    });

    var jwt = builder.Configuration.GetSection(JwtOptions.SectionName).Get<JwtOptions>() ?? new JwtOptions();
    if (string.IsNullOrWhiteSpace(jwt.SigningKey) || jwt.SigningKey.Length < 32)
    {
        throw new InvalidOperationException("Jwt:SigningKey must be at least 32 characters.");
    }

    if (!builder.Environment.IsDevelopment()
        && !builder.Environment.IsEnvironment("Testing")
        && jwt.SigningKey.Contains("CHANGE_ME", StringComparison.Ordinal))
    {
        throw new InvalidOperationException("Jwt:SigningKey must be replaced before running outside Development.");
    }

    builder.Services.AddHealthPalInfrastructure(builder.Configuration);
    builder.Services.AddHttpContextAccessor();
    builder.Services.AddScoped<ICurrentUser, CurrentUser>();
    builder.Services.AddProblemDetails();

    var jsonOptions = (JsonSerializerOptions options) =>
    {
        options.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
        options.DefaultIgnoreCondition = JsonIgnoreCondition.Never;
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false));
        options.Converters.Add(new UtcDateTimeJsonConverter());
        options.Converters.Add(new NullableUtcDateTimeJsonConverter());
    };

    builder.Services.AddControllers()
        .AddJsonOptions(options => jsonOptions(options.JsonSerializerOptions));
    builder.Services.ConfigureHttpJsonOptions(options => jsonOptions(options.SerializerOptions));
    builder.Services.Configure<JsonOptions>(options => jsonOptions(options.JsonSerializerOptions));

    builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddJwtBearer(options =>
        {
            options.MapInboundClaims = false;
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidateAudience = true,
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                ValidIssuer = jwt.Issuer,
                ValidAudience = jwt.Audience,
                IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwt.SigningKey)),
                ClockSkew = TimeSpan.FromSeconds(30),
                NameClaimType = JwtRegisteredClaimNames.Sub,
                RoleClaimType = ClaimTypes.Role
            };
            options.Events = new JwtBearerEvents
            {
                OnChallenge = async context =>
                {
                    context.HandleResponse();
                    context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                    context.Response.ContentType = "application/problem+json";
                    await context.Response.WriteAsJsonAsync(new ProblemDetails
                    {
                        Title = "Unauthorized",
                        Detail = "Authentication is required.",
                        Status = StatusCodes.Status401Unauthorized,
                        Type = "https://tools.ietf.org/html/rfc9110#section-15.5.2"
                    });
                },
                OnForbidden = async context =>
                {
                    context.Response.StatusCode = StatusCodes.Status403Forbidden;
                    context.Response.ContentType = "application/problem+json";
                    await context.Response.WriteAsJsonAsync(new ProblemDetails
                    {
                        Title = "Forbidden",
                        Detail = "You are not allowed to access this resource.",
                        Status = StatusCodes.Status403Forbidden,
                        Type = "https://tools.ietf.org/html/rfc9110#section-15.5.4"
                    });
                }
            };
        });
    builder.Services.AddAuthorization();

    var testing = builder.Environment.IsEnvironment("Testing");
    builder.Services.AddRateLimiter(options =>
    {
        options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
        options.OnRejected = async (context, token) =>
        {
            context.HttpContext.Response.ContentType = "application/problem+json";
            await context.HttpContext.Response.WriteAsJsonAsync(
                new ProblemDetails
                {
                    Title = "Too Many Requests",
                    Detail = "Rate limit exceeded.",
                    Status = StatusCodes.Status429TooManyRequests,
                    Type = "https://tools.ietf.org/html/rfc6585#section-4"
                },
                token);
        };
        options.AddPolicy("auth", httpContext =>
            RateLimitPartition.GetFixedWindowLimiter(
                httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = testing ? 10_000 : 10,
                    Window = TimeSpan.FromMinutes(1),
                    QueueLimit = 0,
                    AutoReplenishment = true
                }));
    });

    builder.Services.AddHealthChecks()
        .AddNpgSql(
            sp => PostgresConnection.Resolve(sp.GetRequiredService<IConfiguration>()),
            name: "postgres",
            tags: ["ready"]);

    builder.Services.AddEndpointsApiExplorer();
    builder.Services.AddSwaggerGen(options =>
    {
        options.SwaggerDoc("v1", new OpenApiInfo
        {
            Title = "HealthPal API",
            Version = "v1",
            Description = "Authentication, profile, health sync, dashboard and history APIs."
        });
        options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
        {
            Description = "JWT Authorization header using the Bearer scheme.",
            Name = "Authorization",
            In = ParameterLocation.Header,
            Type = SecuritySchemeType.Http,
            Scheme = "bearer",
            BearerFormat = "JWT"
        });
        options.AddSecurityRequirement(new OpenApiSecurityRequirement
        {
            {
                new OpenApiSecurityScheme
                {
                    Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
                },
                Array.Empty<string>()
            }
        });
    });

    if (builder.Environment.IsDevelopment())
    {
        var origins = builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? [];
        builder.Services.AddCors(options =>
        {
            options.AddPolicy("dev", policy =>
            {
                policy.WithOrigins(origins.Length == 0
                        ? ["http://localhost:5080", "http://127.0.0.1:5080"]
                        : origins)
                    .AllowAnyHeader()
                    .AllowAnyMethod();
            });
        });
    }

    var app = builder.Build();

    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<HealthPalDbContext>();
        await db.Database.MigrateAsync();
    }

    if (app.Environment.IsDevelopment())
    {
        await DevelopmentSeed.SeedAsync(app.Services, CancellationToken.None);
    }

    app.UseMiddleware<CorrelationIdMiddleware>();
    app.UseSerilogRequestLogging(options =>
    {
        options.EnrichDiagnosticContext = (diagnosticContext, httpContext) =>
        {
            if (httpContext.Items.TryGetValue(CorrelationIdMiddleware.HeaderName, out var correlationId))
            {
                diagnosticContext.Set("CorrelationId", correlationId);
            }

            var userId = httpContext.User.FindFirstValue(ClaimTypes.NameIdentifier);
            if (!string.IsNullOrEmpty(userId))
            {
                diagnosticContext.Set("UserId", userId);
            }
        };
    });
    app.UseMiddleware<ExceptionMappingMiddleware>();
    app.UseMiddleware<SecurityHeadersMiddleware>();

    // Kestrel in this process binds HTTP :5080 only. Redirect to HTTPS when
    // the process actually listens on HTTPS, or a reverse proxy forwarded it.
    var urls = builder.Configuration["ASPNETCORE_URLS"]
        ?? Environment.GetEnvironmentVariable("ASPNETCORE_URLS")
        ?? string.Empty;
    var httpsBound = urls.Contains("https://", StringComparison.OrdinalIgnoreCase);
    if (!app.Environment.IsDevelopment()
        && !app.Environment.IsEnvironment("Testing")
        && httpsBound)
    {
        app.UseHsts();
        app.UseHttpsRedirection();
    }

    if (!app.Environment.IsProduction())
    {
        app.UseSwagger();
        app.UseSwaggerUI();
    }

    if (app.Environment.IsDevelopment())
    {
        app.UseCors("dev");
    }

    app.UseAuthentication();
    app.UseAuthorization();
    app.UseRateLimiter();
    app.MapControllers();
    app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false });
    app.MapHealthChecks("/health/ready", new HealthCheckOptions
    {
        Predicate = check => check.Tags.Contains("ready")
    });

    await app.RunAsync();
}
catch (HostAbortedException)
{
    throw;
}
catch (Exception ex)
{
    Log.Fatal(ex, "HealthPal API terminated unexpectedly");
    throw;
}
finally
{
    await Log.CloseAndFlushAsync();
}

public partial class Program
{
    protected Program()
    {
    }
}
