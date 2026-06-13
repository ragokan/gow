# The Go binary is compiled on the host (Go 1.26) into go-app/benchapp by
# bench/run.sh, then packaged into a minimal Alpine image. Build context is the
# benchmark/ directory.
FROM alpine:latest
WORKDIR /app
COPY go-app/benchapp /app/benchapp
EXPOSE 8080
ENV PORT=8080
ENTRYPOINT ["/app/benchapp"]
