using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using HealthPal.Application.Contracts;

namespace HealthPal.IntegrationTests;

internal static class TestJson
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    public static StringContent Body(object value) =>
        new(JsonSerializer.Serialize(value, Options), Encoding.UTF8, "application/json");

    public static async Task<T> Read<T>(HttpResponseMessage response)
    {
        var json = await response.Content.ReadAsStringAsync();
        var value = JsonSerializer.Deserialize<T>(json, Options);
        return value ?? throw new InvalidOperationException($"Unable to deserialize {typeof(T).Name} from: {json}");
    }

    public static void Bearer(HttpClient client, string accessToken)
    {
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
    }

    public static async Task<AuthSessionDto> RegisterAsync(
        HttpClient client,
        string? email = null,
        string password = "HealthPal123",
        string name = "Test User")
    {
        email ??= $"user-{Guid.NewGuid():N}@healthpal.app";
        var response = await client.PostAsync(
            "/api/v1/auth/register",
            Body(new RegisterRequest { Name = name, Email = email, Password = password }));
        response.EnsureSuccessStatusCode();
        return await Read<AuthSessionDto>(response);
    }
}
