package gow

import "fmt"

// ShouldNoError prints err when err is non-nil and shouldLog is true.
func ShouldNoError(err error, shouldLog bool, msg ...string) {
	if err != nil && shouldLog {
		if len(msg) > 0 {
			fmt.Printf("%s: %v\n", msg[0], err)
		} else {
			fmt.Printf("Error: %v\n", err)
		}
	}
}
