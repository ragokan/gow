# Multi-stage build for the ASP.NET Core 10 + EF Core 10 app.
# Build context is the benchmark/ directory (needs certs/ for the egress proxy CA).
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
# Trust the transparent egress-proxy CA so NuGet restore over TLS succeeds.
COPY certs/*.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates
WORKDIR /src
COPY dotnet-app/BenchApi.csproj ./
RUN dotnet restore
COPY dotnet-app/ ./
RUN dotnet publish -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app ./
EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production
ENV DOTNET_gcServer=1
ENTRYPOINT ["dotnet", "BenchApi.dll"]
