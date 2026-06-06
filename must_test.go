package gow

import (
	"errors"
	"testing"
)

func TestMustReturnsValue(t *testing.T) {
	t.Parallel()

	got := Must("ok", nil)
	if got != "ok" {
		t.Fatalf("Must() = %q, want %q", got, "ok")
	}
}

func TestMustPanicsOnError(t *testing.T) {
	t.Parallel()

	defer func() {
		if recover() == nil {
			t.Fatal("Must() did not panic")
		}
	}()

	Must("", errors.New("boom"))
}

func TestMustNoErrorPanicsOnError(t *testing.T) {
	t.Parallel()

	defer func() {
		if recover() == nil {
			t.Fatal("MustNoError() did not panic")
		}
	}()

	MustNoError(errors.New("boom"))
}
