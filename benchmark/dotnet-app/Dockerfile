# Native AOT build for the ASP.NET Core 10 + raw Npgsql app.
# Build context is the benchmark/ directory (needs certs/ for the egress proxy CA).
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
# Trust the transparent egress-proxy CA so NuGet restore over TLS succeeds.
COPY certs/*.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates
# Native AOT toolchain (clang + zlib).
RUN apt-get update && apt-get install -y --no-install-recommends clang zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY dotnet-app/BenchApi.csproj ./
RUN dotnet restore -r linux-x64
COPY dotnet-app/ ./
RUN dotnet publish -c Release -r linux-x64 -o /app --no-restore /p:PublishAot=true

# Minimal native base (no .NET runtime needed for an AOT binary).
FROM mcr.microsoft.com/dotnet/runtime-deps:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/BenchApi ./
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production
ENV Logging__LogLevel__Default=Warning
ENV Logging__LogLevel__Microsoft.AspNetCore=Warning
ENTRYPOINT ["./BenchApi"]
