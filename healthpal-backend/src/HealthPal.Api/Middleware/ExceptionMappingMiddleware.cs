using System.Text.Json;
using HealthPal.Application.Exceptions;
using Microsoft.AspNetCore.Mvc;

namespace HealthPal.Api.Middleware;

public sealed class ExceptionMappingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<ExceptionMappingMiddleware> _logger;
    private readonly IHostEnvironment _environment;

    public ExceptionMappingMiddleware(
        RequestDelegate next,
        ILogger<ExceptionMappingMiddleware> logger,
        IHostEnvironment environment)
    {
        _next = next;
        _logger = logger;
        _environment = environment;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (AppValidationException ex)
        {
            await WriteProblemAsync(context, new ValidationProblemDetails(ex.Errors.ToDictionary(static pair => pair.Key, static pair => pair.Value, StringComparer.Ordinal))
            {
                Title = ex.Title,
                Detail = ex.Message,
                Status = ex.StatusCode,
                Type = "https://tools.ietf.org/html/rfc9110#section-15.5.1"
            });
        }
        catch (ConflictAppException ex)
        {
            var problem = new ValidationProblemDetails
            {
                Title = ex.Title,
                Detail = ex.Message,
                Status = ex.StatusCode,
                Type = "https://tools.ietf.org/html/rfc9110#section-15.5.10"
            };
            if (!string.IsNullOrWhiteSpace(ex.Field))
            {
                problem.Errors.Add(ex.Field, [ex.Message]);
            }

            await WriteProblemAsync(context, problem);
        }
        catch (AppException ex)
        {
            await WriteProblemAsync(context, new ProblemDetails
            {
                Title = ex.Title,
                Detail = ex.Message,
                Status = ex.StatusCode,
                Type = $"https://httpstatuses.com/{ex.StatusCode}"
            });
        }
        catch (JsonException)
        {
            await WriteProblemAsync(context, new ProblemDetails
            {
                Title = "Invalid JSON",
                Detail = "The request body could not be parsed.",
                Status = StatusCodes.Status400BadRequest,
                Type = "https://tools.ietf.org/html/rfc9110#section-15.5.1"
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unhandled exception");
            var detail = _environment.IsDevelopment() || _environment.IsEnvironment("Testing")
                ? ex.Message
                : "An unexpected error occurred.";
            await WriteProblemAsync(context, new ProblemDetails
            {
                Title = "Internal Server Error",
                Detail = detail,
                Status = StatusCodes.Status500InternalServerError,
                Type = "https://tools.ietf.org/html/rfc9110#section-15.6.1"
            });
        }
    }

    private static async Task WriteProblemAsync(HttpContext context, ProblemDetails problem)
    {
        if (context.Response.HasStarted)
        {
            return;
        }

        context.Response.Clear();
        context.Response.StatusCode = problem.Status ?? StatusCodes.Status500InternalServerError;
        context.Response.ContentType = "application/problem+json";
        if (problem is ValidationProblemDetails validation)
        {
            await context.Response.WriteAsJsonAsync(new Dictionary<string, object?>
            {
                ["type"] = validation.Type,
                ["title"] = validation.Title,
                ["status"] = validation.Status,
                ["detail"] = validation.Detail,
                ["errors"] = validation.Errors
            });
            return;
        }

        await context.Response.WriteAsJsonAsync(problem);
    }
}
