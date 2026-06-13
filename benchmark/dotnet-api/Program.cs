// Minimal CRUD HTTP service for benchmarking the .NET stack against an
// equivalent Go service. Published as a Native AOT binary.
//
// Best-practice choices for max throughput on a fair footing with the Go app:
//   * Native AOT (no JIT warmup, smaller/faster startup) + Server GC.
//   * Raw Npgsql with hand-mapped data readers (no ORM/reflection overhead,
//     fully AOT/trim-safe) -- the closest analogue to sqlc's generated SQL.
//   * Auto-prepared statements (parity with pgx, which caches prepares).
//   * Source-generated System.Text.Json and TypedResults (AOT-friendly).
using System.Text.Json.Serialization;
using Npgsql;

var builder = WebApplication.CreateSlimBuilder(args);

// Quiet per-request logging so we measure the server, not the console logger
// (the Go app does no per-request logging; matches a production log level).
builder.Logging.ClearProviders();
builder.Logging.SetMinimumLevel(LogLevel.Warning);

builder.Services.ConfigureHttpJsonOptions(o =>
{
    o.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default);
});

var dsn = Environment.GetEnvironmentVariable("DATABASE_URL")
          ?? "Host=127.0.0.1;Port=5432;Database=benchdb;Username=bench;Password=benchpass";

var csb = new NpgsqlConnectionStringBuilder(dsn)
{
    // Match the Go app's pgxpool sizing for a fair comparison.
    MaxPoolSize = 50,
    MinPoolSize = 10,
    Pooling = true,
    // Auto-prepare hot statements (pgx caches prepared statements by default).
    MaxAutoPrepare = 20,
    AutoPrepareMinUsages = 2,
};

var dataSource = NpgsqlDataSource.Create(csb.ConnectionString);
builder.Services.AddSingleton(dataSource);

var app = builder.Build();

const string cols = "id, name, email, age, created_at, updated_at";

static User MapUser(NpgsqlDataReader r) => new(
    r.GetInt64(0), r.GetString(1), r.GetString(2), r.GetInt32(3),
    r.GetFieldValue<DateTime>(4), r.GetFieldValue<DateTime>(5));

app.MapGet("/health", () => TypedResults.Ok(new StatusResponse("ok")));

app.MapPost("/users", async (CreateUserReq req, NpgsqlDataSource ds) =>
{
    await using var cmd = ds.CreateCommand(
        $"INSERT INTO users (name, email, age) VALUES ($1, $2, $3) RETURNING {cols}");
    cmd.Parameters.Add(new() { Value = req.Name });
    cmd.Parameters.Add(new() { Value = req.Email });
    cmd.Parameters.Add(new() { Value = req.Age });
    await using var r = await cmd.ExecuteReaderAsync();
    await r.ReadAsync();
    var user = MapUser(r);
    return Results.Created($"/users/{user.Id}", user);
});

app.MapGet("/users/{id:long}", async (long id, NpgsqlDataSource ds) =>
{
    await using var cmd = ds.CreateCommand($"SELECT {cols} FROM users WHERE id = $1");
    cmd.Parameters.Add(new() { Value = id });
    await using var r = await cmd.ExecuteReaderAsync();
    return await r.ReadAsync()
        ? Results.Ok(MapUser(r))
        : Results.NotFound(new ErrorResponse("not found"));
});

app.MapGet("/users", async (int? limit, int? offset, NpgsqlDataSource ds) =>
{
    var lim = limit is > 0 and <= 1000 ? limit.Value : 20;
    var off = offset is >= 0 ? offset.Value : 0;
    await using var cmd = ds.CreateCommand($"SELECT {cols} FROM users ORDER BY id LIMIT $1 OFFSET $2");
    cmd.Parameters.Add(new() { Value = lim });
    cmd.Parameters.Add(new() { Value = off });
    var users = new List<User>(lim);
    await using var r = await cmd.ExecuteReaderAsync();
    while (await r.ReadAsync()) users.Add(MapUser(r));
    return Results.Ok(users);
});

app.MapPut("/users/{id:long}", async (long id, UpdateUserReq req, NpgsqlDataSource ds) =>
{
    await using var cmd = ds.CreateCommand(
        $"UPDATE users SET name = $2, email = $3, age = $4, updated_at = now() WHERE id = $1 RETURNING {cols}");
    cmd.Parameters.Add(new() { Value = id });
    cmd.Parameters.Add(new() { Value = req.Name });
    cmd.Parameters.Add(new() { Value = req.Email });
    cmd.Parameters.Add(new() { Value = req.Age });
    await using var r = await cmd.ExecuteReaderAsync();
    return await r.ReadAsync()
        ? Results.Ok(MapUser(r))
        : Results.NotFound(new ErrorResponse("not found"));
});

app.MapDelete("/users/{id:long}", async (long id, NpgsqlDataSource ds) =>
{
    await using var cmd = ds.CreateCommand("DELETE FROM users WHERE id = $1");
    cmd.Parameters.Add(new() { Value = id });
    await cmd.ExecuteNonQueryAsync();
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
[JsonSerializable(typeof(List<User>))]
[JsonSerializable(typeof(CreateUserReq))]
[JsonSerializable(typeof(UpdateUserReq))]
[JsonSerializable(typeof(StatusResponse))]
[JsonSerializable(typeof(ErrorResponse))]
internal partial class AppJsonContext : JsonSerializerContext;
