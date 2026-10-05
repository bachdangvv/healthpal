using System.Net;
using FluentAssertions;
using HealthPal.Application.Contracts;

namespace HealthPal.IntegrationTests;

[Collection("api")]
public sealed class AuthTests
{
    private readonly HealthPalApiFactory _factory;

    public AuthTests(HealthPalApiFactory factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task Register_and_login_return_session()
    {
        using var client = _factory.CreateClient();
        var email = $"auth-{Guid.NewGuid():N}@healthpal.app";
        var registered = await TestJson.RegisterAsync(client, email, name: "Minh Anh");
        registered.User.Name.Should().Be("Minh Anh");
        registered.User.Email.Should().Be(email);
        registered.Tokens.AccessToken.Should().NotBeNullOrWhiteSpace();
        registered.Tokens.RefreshToken.Should().NotBeNullOrWhiteSpace();

        var login = await client.PostAsync(
            "/api/v1/auth/login",
            TestJson.Body(new LoginRequest { Email = email, Password = "HealthPal123" }));
        login.StatusCode.Should().Be(HttpStatusCode.OK);
        var session = await TestJson.Read<AuthSessionDto>(login);
        session.User.Id.Should().Be(registered.User.Id);

        TestJson.Bearer(client, session.Tokens.AccessToken);
        var me = await client.GetAsync("/api/v1/auth/me");
        me.StatusCode.Should().Be(HttpStatusCode.OK);
        var user = await TestJson.Read<AuthUserDto>(me);
        user.Email.Should().Be(email);
    }

    [Fact]
    public async Task Login_does_not_reveal_whether_email_exists()
    {
        using var client = _factory.CreateClient();
        var unknown = await client.PostAsync(
            "/api/v1/auth/login",
            TestJson.Body(new LoginRequest { Email = $"missing-{Guid.NewGuid():N}@healthpal.app", Password = "HealthPal123" }));
        var email = $"exists-{Guid.NewGuid():N}@healthpal.app";
        await TestJson.RegisterAsync(client, email);
        var wrongPassword = await client.PostAsync(
            "/api/v1/auth/login",
            TestJson.Body(new LoginRequest { Email = email, Password = "WrongPass1" }));

        unknown.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        wrongPassword.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        var unknownBody = await unknown.Content.ReadAsStringAsync();
        var wrongBody = await wrongPassword.Content.ReadAsStringAsync();
        unknownBody.Should().Be(wrongBody);
    }

    [Fact]
    public async Task Refresh_rotates_and_reuse_revokes_family()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        var firstRefresh = session.Tokens.RefreshToken;

        var rotatedResponse = await client.PostAsync(
            "/api/v1/auth/refresh",
            TestJson.Body(new RefreshRequest { RefreshToken = firstRefresh }));
        rotatedResponse.StatusCode.Should().Be(HttpStatusCode.OK);
        var rotated = await TestJson.Read<TokenPairDto>(rotatedResponse);
        rotated.RefreshToken.Should().NotBe(firstRefresh);

        var reuse = await client.PostAsync(
            "/api/v1/auth/refresh",
            TestJson.Body(new RefreshRequest { RefreshToken = firstRefresh }));
        reuse.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        var familyRevoked = await client.PostAsync(
            "/api/v1/auth/refresh",
            TestJson.Body(new RefreshRequest { RefreshToken = rotated.RefreshToken }));
        familyRevoked.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Logout_revokes_refresh_token()
    {
        using var client = _factory.CreateClient();
        var session = await TestJson.RegisterAsync(client);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var logout = await client.PostAsync(
            "/api/v1/auth/logout",
            TestJson.Body(new LogoutRequest { RefreshToken = session.Tokens.RefreshToken }));
        logout.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var refresh = await client.PostAsync(
            "/api/v1/auth/refresh",
            TestJson.Body(new RefreshRequest { RefreshToken = session.Tokens.RefreshToken }));
        refresh.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Change_password_revokes_sessions_and_requires_new_password()
    {
        using var client = _factory.CreateClient();
        var email = $"pwd-{Guid.NewGuid():N}@healthpal.app";
        var session = await TestJson.RegisterAsync(client, email);
        TestJson.Bearer(client, session.Tokens.AccessToken);
        var changed = await client.PostAsync(
            "/api/v1/auth/change-password",
            TestJson.Body(new ChangePasswordRequest
            {
                CurrentPassword = "HealthPal123",
                NewPassword = "HealthPal456"
            }));
        changed.StatusCode.Should().Be(HttpStatusCode.NoContent);

        var oldLogin = await client.PostAsync(
            "/api/v1/auth/login",
            TestJson.Body(new LoginRequest { Email = email, Password = "HealthPal123" }));
        oldLogin.StatusCode.Should().Be(HttpStatusCode.Unauthorized);

        var newLogin = await client.PostAsync(
            "/api/v1/auth/login",
            TestJson.Body(new LoginRequest { Email = email, Password = "HealthPal456" }));
        newLogin.StatusCode.Should().Be(HttpStatusCode.OK);

        var refresh = await client.PostAsync(
            "/api/v1/auth/refresh",
            TestJson.Body(new RefreshRequest { RefreshToken = session.Tokens.RefreshToken }));
        refresh.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }

    [Fact]
    public async Task Duplicate_register_is_conflict()
    {
        using var client = _factory.CreateClient();
        var email = $"dup-{Guid.NewGuid():N}@healthpal.app";
        await TestJson.RegisterAsync(client, email);
        var duplicate = await client.PostAsync(
            "/api/v1/auth/register",
            TestJson.Body(new RegisterRequest { Name = "Other", Email = email, Password = "HealthPal123" }));
        duplicate.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Unauthenticated_me_is_401()
    {
        using var client = _factory.CreateClient();
        var me = await client.GetAsync("/api/v1/auth/me");
        me.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
