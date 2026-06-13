using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace BenchApi.Data;

// Allows `dotnet ef migrations add` to build the context without a running database.
public class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql("Host=localhost;Database=bench;Username=bench;Password=bench")
            .Options;
        return new AppDbContext(options);
    }
}
