using BenchApi.Models;
using Microsoft.EntityFrameworkCore;

namespace BenchApi.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        var user = modelBuilder.Entity<User>();
        user.ToTable("users");
        user.HasKey(u => u.Id);
        user.Property(u => u.Id).HasColumnName("id").UseIdentityByDefaultColumn();
        user.Property(u => u.Name).HasColumnName("name").IsRequired();
        user.Property(u => u.Email).HasColumnName("email").IsRequired();
        user.Property(u => u.Age).HasColumnName("age").IsRequired();
        user.Property(u => u.CreatedAt).HasColumnName("created_at")
            .HasDefaultValueSql("now()");
        user.Property(u => u.UpdatedAt).HasColumnName("updated_at")
            .HasDefaultValueSql("now()");
        user.HasIndex(u => u.Email).HasDatabaseName("idx_users_email");
    }
}
