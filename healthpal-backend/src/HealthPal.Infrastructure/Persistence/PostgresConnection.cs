using Microsoft.Extensions.Configuration;
using Npgsql;

namespace HealthPal.Infrastructure.Persistence;

public static class PostgresConnection
{
    public static string Resolve(IConfiguration configuration)
    {
        var connection = configuration.GetConnectionString("DefaultConnection")
            ?? throw new InvalidOperationException("Connection string 'DefaultConnection' is missing.");
        var password = configuration["POSTGRES_PASSWORD"];
        if (string.IsNullOrWhiteSpace(password))
        {
            return connection;
        }

        var builder = new NpgsqlConnectionStringBuilder(connection)
        {
            Password = password
        };
        return builder.ConnectionString;
    }
}
