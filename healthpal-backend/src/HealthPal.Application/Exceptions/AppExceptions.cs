namespace HealthPal.Application.Exceptions;

public abstract class AppException : Exception
{
    protected AppException(string title, string message, int statusCode)
        : base(message)
    {
        Title = title;
        StatusCode = statusCode;
    }

    public string Title { get; }
    public int StatusCode { get; }
}

public sealed class UnauthorizedAppException : AppException
{
    public UnauthorizedAppException(string message = "Invalid credentials.")
        : base("Unauthorized", message, 401)
    {
    }
}

public sealed class ForbiddenAppException : AppException
{
    public ForbiddenAppException(string message = "Forbidden.")
        : base("Forbidden", message, 403)
    {
    }
}

public sealed class NotFoundAppException : AppException
{
    public NotFoundAppException(string message = "Resource not found.")
        : base("Not Found", message, 404)
    {
    }
}

public sealed class ConflictAppException : AppException
{
    public ConflictAppException(string message, string? field = null)
        : base("Conflict", message, 409)
    {
        Field = field;
    }

    public string? Field { get; }
}

public sealed class PayloadTooLargeAppException : AppException
{
    public PayloadTooLargeAppException(string message)
        : base("Payload Too Large", message, 413)
    {
    }
}

public sealed class AppValidationException : AppException
{
    public AppValidationException(IReadOnlyDictionary<string, string[]> errors)
        : base("Validation failed", "One or more validation errors occurred.", 400)
    {
        Errors = errors;
    }

    public AppValidationException(string field, string error)
        : this(new Dictionary<string, string[]>(StringComparer.Ordinal) { [field] = [error] })
    {
    }

    public IReadOnlyDictionary<string, string[]> Errors { get; }
}
