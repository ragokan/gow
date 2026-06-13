-- Two isolated databases in one shared Postgres instance so each app owns its
-- own migration history while running against identical engine/resources.
CREATE DATABASE bench_go;
CREATE DATABASE bench_dotnet;
