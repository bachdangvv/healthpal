using FluentAssertions;
using HealthPal.Application.Security;

namespace HealthPal.UnitTests;

public sealed class TokenHashTests
{
    [Fact]
    public void CreateRefreshToken_is_at_least_32_bytes_decoded()
    {
        var token = TokenHash.CreateRefreshToken();
        token.Should().NotBeNullOrWhiteSpace();
        var padded = token.Replace('-', '+').Replace('_', '/');
        switch (padded.Length % 4)
        {
            case 2:
                padded += "==";
                break;
            case 3:
                padded += "=";
                break;
        }

        var bytes = Convert.FromBase64String(padded);
        bytes.Length.Should().BeGreaterThanOrEqualTo(32);
    }

    [Fact]
    public void Sha256Hex_is_stable_and_hex()
    {
        var hash = TokenHash.Sha256Hex("healthpal");
        hash.Should().Be(TokenHash.Sha256Hex("healthpal"));
        hash.Should().HaveLength(64);
        hash.Should().MatchRegex("^[0-9a-f]{64}$");
        hash.Should().NotBe(TokenHash.Sha256Hex("other"));
    }
}
