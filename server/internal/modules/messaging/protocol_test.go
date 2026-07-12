package messaging

import "testing"

func TestCommandMessagesUseSyncOnce(t *testing.T) {
	header, err := HeaderFor(TypeCMD, false)
	if err != nil {
		t.Fatal(err)
	}
	if header.SyncOnce != 1 || header.NoPersist != 1 {
		t.Fatalf("header=%+v", header)
	}
}

func TestSystemTypeMustExceedReservedBoundary(t *testing.T) {
	if _, err := HeaderFor(TypeText, true); err == nil {
		t.Fatal("expected system type rejection")
	}
}
