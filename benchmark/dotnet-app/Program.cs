using System.Text.Json.Serialization;
using BenchApi;
using Npgsql;

var builder = WebApplication.CreateSlimBuilder(args);

// Source-generated JSON (required for Native AOT — no reflection-based serializer).
builder.Services.ConfigureHttpJsonOptions(options =>
{
    options.SerializerOptions.TypeInfoResolverChain.Insert(0, AppJsonContext.Default);
});

var connectionString = Environment.GetEnvironmentVariable("DATABASE_URL")
    ?? "Host=localhost;Database=bench;Username=bench;Password=bench";

var maxPool = int.TryParse(Environment.GetEnvironmentVariable("DB_MAX_CONNS"), out var mp) ? mp : 30;
var minPool = int.TryParse(Environment.GetEnvironmentVariable("DB_MIN_CONNS"), out var np) ? np : 10;

// NpgsqlDataSource is the modern, pooled, recommended entry point.
var dsBuilder = new NpgsqlDataSourceBuilder(connectionString)
{
    ConnectionStringBuilder =
    {
        MaxPoolSize = maxPool,
        MinPoolSize = minPool,
        MaxAutoPrepare = 32, // server-side prepared-statement caching
    }
};
var dataSource = dsBuilder.Build();
builder.Services.AddSingleton(dataSource);

var app = builder.Build();

// Apply SQL migrations at startup.
await Migrations.RunAsync(dataSource);

const string Cols = "id, name, email, age, created_at, updated_at";

app.MapGet("/health", () => Results.Ok(new StatusResponse("ok")));

app.MapPost("/users", async (UserInput input, NpgsqlDataSource db) =>
{
    await using var cmd = db.CreateCommand(
        $"INSERT INTO users (name, email, age) VALUES ($1, $2, $3) RETURNING {Cols}");
    cmd.Parameters.AddWithValue(input.Name);
    cmd.Parameters.AddWithValue(input.Email);
    cmd.Parameters.AddWithValue(input.Age);
    await using var r = await cmd.ExecuteReaderAsync();
    await r.ReadAsync();
    var user = ReadUser(r);
    return Results.Created($"/users/{user.Id}", user);
});

app.MapGet("/users/{id:long}", async (long id, NpgsqlDataSource db) =>
{
    await using var cmd = db.CreateCommand($"SELECT {Cols} FROM users WHERE id = $1");
    cmd.Parameters.AddWithValue(id);
    await using var r = await cmd.ExecuteReaderAsync();
    return await r.ReadAsync()
        ? Results.Ok(ReadUser(r))
        : Results.NotFound(new ErrorResponse("not found"));
});

app.MapGet("/users", async (int? limit, int? offset, NpgsqlDataSource db) =>
{
    await using var cmd = db.CreateCommand(
        $"SELECT {Cols} FROM users ORDER BY id DESC LIMIT $1 OFFSET $2");
    cmd.Parameters.AddWithValue(limit ?? 20);
    cmd.Parameters.AddWithValue(offset ?? 0);
    var users = new List<User>();
    await using var r = await cmd.ExecuteReaderAsync();
    while (await r.ReadAsync())
        users.Add(ReadUser(r));
    return Results.Ok(users);
});

app.MapPut("/users/{id:long}", async (long id, UserInput input, NpgsqlDataSource db) =>
{
    await using var cmd = db.CreateCommand(
        $"UPDATE users SET name = $2, email = $3, age = $4, updated_at = now() WHERE id = $1 RETURNING {Cols}");
    cmd.Parameters.AddWithValue(id);
    cmd.Parameters.AddWithValue(input.Name);
    cmd.Parameters.AddWithValue(input.Email);
    cmd.Parameters.AddWithValue(input.Age);
    await using var r = await cmd.ExecuteReaderAsync();
    return await r.ReadAsync()
        ? Results.Ok(ReadUser(r))
        : Results.NotFound(new ErrorResponse("not found"));
});

app.MapDelete("/users/{id:long}", async (long id, NpgsqlDataSource db) =>
{
    await using var cmd = db.CreateCommand("DELETE FROM users WHERE id = $1");
    cmd.Parameters.AddWithValue(id);
    var rows = await cmd.ExecuteNonQueryAsync();
    return rows == 0 ? Results.NotFound(new ErrorResponse("not found")) : Results.NoContent();
});

app.Run();

static User ReadUser(NpgsqlDataReader r) => new(
    r.GetInt64(0), r.GetString(1), r.GetString(2), r.GetInt32(3),
    r.GetDateTime(4), r.GetDateTime(5));

namespace BenchApi
{
    // Explicit JSON names keep the wire contract byte-identical to the Go app.
    public record User(
        [property: JsonPropertyName("id")] long Id,
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("email")] string Email,
        [property: JsonPropertyName("age")] int Age,
        [property: JsonPropertyName("created_at")] DateTime CreatedAt,
        [property: JsonPropertyName("updated_at")] DateTime UpdatedAt);

    public record UserInput(
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("email")] string Email,
        [property: JsonPropertyName("age")] int Age);

    public record StatusResponse([property: JsonPropertyName("status")] string Status);
    public record ErrorResponse([property: JsonPropertyName("error")] string Error);

    [JsonSerializable(typeof(User))]
    [JsonSerializable(typeof(List<User>))]
    [JsonSerializable(typeof(UserInput))]
    [JsonSerializable(typeof(StatusResponse))]
    [JsonSerializable(typeof(ErrorResponse))]
    public partial class AppJsonContext : JsonSerializerContext;
}
