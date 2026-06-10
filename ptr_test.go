package gow

import "testing"

func TestPtr(t *testing.T) {
	got := Ptr(10)
	if got == nil {
		t.Fatal("Ptr returned nil")
	}
	if *got != 10 {
		t.Fatalf("Ptr returned pointer to %d, want 10", *got)
	}
}
