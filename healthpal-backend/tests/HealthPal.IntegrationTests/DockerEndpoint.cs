using System.Runtime.CompilerServices;
using Testcontainers.PostgreSql;

namespace HealthPal.IntegrationTests;

internal static class DockerEndpoint
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        if (OperatingSystem.IsWindows()
            && string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("DOCKER_HOST")))
        {
            Environment.SetEnvironmentVariable("DOCKER_HOST", WindowsEndpoint());
        }
    }

    public static PostgreSqlBuilder Postgres(string database, string password) =>
        new PostgreSqlBuilder()
            .WithImage("postgres:16-alpine")
            .WithDatabase(database)
            .WithUsername("healthpal")
            .WithPassword(password)
            .WithDockerEndpoint(WindowsEndpoint());

    private static string WindowsEndpoint()
    {
        if (!OperatingSystem.IsWindows())
        {
            return "unix:///var/run/docker.sock";
        }

        string[] pipes;
        try
        {
            pipes = Directory.GetFiles(@"\\.\pipe\");
        }
        catch (IOException)
        {
            pipes = [];
        }

        foreach (var pipe in new[] { "dockerDesktopLinuxEngine", "docker_engine_linux", "docker_engine" })
        {
            if (pipes.Any(candidate => candidate.EndsWith(pipe, StringComparison.OrdinalIgnoreCase)))
            {
                return $"npipe://./pipe/{pipe}";
            }
        }

        return "npipe://./pipe/docker_engine";
    }
}
