using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using HealthPal.Application.Contracts;

namespace HealthPal.Application.Security;

public static class PayloadCanonicalizer
{
    public static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        WriteIndented = false,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false) }
    };

    public static string Hash(SyncBatchDto batch)
    {
        var json = JsonSerializer.Serialize(batch, JsonOptions);
        return TokenHash.Sha256Hex(json);
    }

    public static string Sha256Utf8(string value)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}
