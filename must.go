package gow

import "fmt"

// Must returns val when err is nil and panics when err is non-nil.
// It is intended for initialization paths where an error should fail fast.
func Must[T any](val T, err error) T {
	if err != nil {
		panic(fmt.Sprintf("Must failed: %v", err))
	}

	return val
}

// MustNoError panics when err is non-nil.
func MustNoError(err error, msg ...string) {
	if err != nil {
		if len(msg) > 0 {
			panic(fmt.Sprintf("%s: %v", msg[0], err))
		}

		panic(err)
	}
}
