package gow

import "crypto/rand"

// RandBool returns a cryptographically random boolean.
func RandBool() bool {
	var b [1]byte
	if _, err := rand.Read(b[:]); err != nil {
		return false
	}

	return b[0]&1 == 1
}
