// Minimal CRUD HTTP service for benchmarking the .NET stack
// (ASP.NET Core Minimal APIs + Npgsql + Dapper, raw SQL) against an
// equivalent Go service. It mirrors the Go app endpoint-for-endpoint.
using System.Text.Json.Serialization;
using Dapper;
using Npgsql;

var builder = WebApplication.CreateSlimBuilder(args);

// Quiet per-request logging so we measure the server, not the console logger.
// (The Go app does no per-request logging; this keeps the comparison fair and
// matches a production logging level.)
builder.Logging.ClearProviders();
builder.Logging.SetMinimumLevel(LogLevel.Warning);

// Source-generated JSON for the request/response DTOs (AOT-friendly, fast).
builder.Services.ConfigureHttpJsonOptions(o =>
{
    o.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default);
});

var dsn = Environment.GetEnvironmentVariable("DATABASE_URL")
          ?? "Host=127.0.0.1;Port=5432;Database=benchdb;Username=bench;Password=benchpass";

// Match the Go app's pgxpool sizing for a fair comparison.
var connStringBuilder = new NpgsqlConnectionStringBuilder(dsn)
{
    MaxPoolSize = 50,
    MinPoolSize = 10,
    Pooling = true,
};

var dataSource = NpgsqlDataSource.Create(connStringBuilder.ConnectionString);
builder.Services.AddSingleton(dataSource);

var app = builder.Build();

const string selectCols = "id, name, email, age, created_at AS CreatedAt, updated_at AS UpdatedAt";

app.MapGet("/health", () => Results.Ok(new StatusResponse("ok")));

app.MapPost("/users", async (CreateUserReq req, NpgsqlDataSource ds) =>
{
    await using var conn = await ds.OpenConnectionAsync();
    var user = await conn.QuerySingleAsync<User>(
        $"INSERT INTO users (name, email, age) VALUES (@Name, @Email, @Age) RETURNING {selectCols}",
        new { req.Name, req.Email, req.Age });
    return Results.Created($"/users/{user.Id}", user);
});

app.MapGet("/users/{id:long}", async (long id, NpgsqlDataSource ds) =>
{
    await using var conn = await ds.OpenConnectionAsync();
    var user = await conn.QuerySingleOrDefaultAsync<User>(
        $"SELECT {selectCols} FROM users WHERE id = @id", new { id });
    return user is null ? Results.NotFound(new ErrorResponse("not found")) : Results.Ok(user);
});

app.MapGet("/users", async (int? limit, int? offset, NpgsqlDataSource ds) =>
{
    var lim = limit is > 0 and <= 1000 ? limit.Value : 20;
    var off = offset is >= 0 ? offset.Value : 0;
    await using var conn = await ds.OpenConnectionAsync();
    var users = await conn.QueryAsync<User>(
        $"SELECT {selectCols} FROM users ORDER BY id LIMIT @lim OFFSET @off",
        new { lim, off });
    return Results.Ok(users);
});

app.MapPut("/users/{id:long}", async (long id, UpdateUserReq req, NpgsqlDataSource ds) =>
{
    await using var conn = await ds.OpenConnectionAsync();
    var user = await conn.QuerySingleOrDefaultAsync<User>(
        $"UPDATE users SET name = @Name, email = @Email, age = @Age, updated_at = now() WHERE id = @id RETURNING {selectCols}",
        new { id, req.Name, req.Email, req.Age });
    return user is null ? Results.NotFound(new ErrorResponse("not found")) : Results.Ok(user);
});

app.MapDelete("/users/{id:long}", async (long id, NpgsqlDataSource ds) =>
{
    await using var conn = await ds.OpenConnectionAsync();
    await conn.ExecuteAsync("DELETE FROM users WHERE id = @id", new { id });
    return Results.NoContent();
});

var port = Environment.GetEnvironmentVariable("PORT") ?? "8081";
app.Run($"http://0.0.0.0:{port}");

public sealed record User(long Id, string Name, string Email, int Age, DateTime CreatedAt, DateTime UpdatedAt);
public sealed record CreateUserReq(string Name, string Email, int Age);
public sealed record UpdateUserReq(string Name, string Email, int Age);
public sealed record StatusResponse(string Status);
public sealed record ErrorResponse(string Error);

[JsonSerializable(typeof(User))]
[JsonSerializable(typeof(IEnumerable<User>))]
[JsonSerializable(typeof(CreateUserReq))]
[JsonSerializable(typeof(UpdateUserReq))]
[JsonSerializable(typeof(StatusResponse))]
[JsonSerializable(typeof(ErrorResponse))]
internal partial class AppJsonContext : JsonSerializerContext;
