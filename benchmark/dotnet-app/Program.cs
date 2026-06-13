using BenchApi.Data;
using BenchApi.Models;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

var connectionString = Environment.GetEnvironmentVariable("DATABASE_URL")
    ?? "Host=localhost;Database=bench;Username=bench;Password=bench";

var maxPool = int.TryParse(Environment.GetEnvironmentVariable("DB_MAX_CONNS"), out var mp) ? mp : 30;
var minPool = int.TryParse(Environment.GetEnvironmentVariable("DB_MIN_CONNS"), out var np) ? np : 10;
if (!connectionString.Contains("Maximum Pool Size", StringComparison.OrdinalIgnoreCase))
{
    connectionString = $"{connectionString};Maximum Pool Size={maxPool};Minimum Pool Size={minPool}";
}

builder.Services.AddDbContextPool<AppDbContext>(options =>
    options.UseNpgsql(connectionString));

builder.Services.ConfigureHttpJsonOptions(o =>
{
    o.SerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.SnakeCaseLower;
});

var app = builder.Build();

// Apply migrations at startup (goose analog).
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
}

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

app.MapPost("/users", async (UserInput input, AppDbContext db) =>
{
    var user = new User { Name = input.Name, Email = input.Email, Age = input.Age };
    db.Users.Add(user);
    await db.SaveChangesAsync();
    return Results.Created($"/users/{user.Id}", user);
});

app.MapGet("/users/{id:long}", async (long id, AppDbContext db) =>
{
    var user = await db.Users.AsNoTracking().FirstOrDefaultAsync(u => u.Id == id);
    return user is null ? Results.NotFound(new { error = "not found" }) : Results.Ok(user);
});

app.MapGet("/users", async (int? limit, int? offset, AppDbContext db) =>
{
    var take = limit ?? 20;
    var skip = offset ?? 0;
    var users = await db.Users.AsNoTracking()
        .OrderByDescending(u => u.Id)
        .Skip(skip)
        .Take(take)
        .ToListAsync();
    return Results.Ok(users);
});

app.MapPut("/users/{id:long}", async (long id, UserInput input, AppDbContext db) =>
{
    var user = await db.Users.FirstOrDefaultAsync(u => u.Id == id);
    if (user is null)
        return Results.NotFound(new { error = "not found" });
    user.Name = input.Name;
    user.Email = input.Email;
    user.Age = input.Age;
    user.UpdatedAt = DateTime.UtcNow;
    await db.SaveChangesAsync();
    return Results.Ok(user);
});

app.MapDelete("/users/{id:long}", async (long id, AppDbContext db) =>
{
    var rows = await db.Users.Where(u => u.Id == id).ExecuteDeleteAsync();
    return rows == 0 ? Results.NotFound(new { error = "not found" }) : Results.NoContent();
});

app.Run();
