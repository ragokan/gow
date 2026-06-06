# gow

Okan's Go utility package.

`gow` is a small collection of helpers used across Okan's Go projects. Keep this package boring: small APIs, no heavy dependencies, and behavior that is easy to inspect.

## Install

```sh
go get github.com/ragokan/gow@latest
```

## Usage

```go
package main

import "github.com/ragokan/gow"

func main() {
	value := gow.Must(loadValue())
	gow.MustNoError(start(value))
}
```

## Release Flow

Go modules are released by pushing semantic version tags.

1. Make and commit the change.
2. Run `go test ./...`.
3. Tag the release:

   ```sh
   git tag v0.1.0
   git push origin v0.1.0
   ```

4. The release workflow creates the GitHub release for the pushed tag.
5. Consumers upgrade with:

   ```sh
   go get github.com/ragokan/gow@v0.1.0
   ```

For breaking changes after `v1.0.0`, follow Go semantic import versioning by moving to a `/v2` module path.
