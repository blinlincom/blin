package authn

import "testing"

func TestPasswordHashAndVerify(t *testing.T) {
	policy := DefaultPasswordPolicy()
	hash, err := policy.Hash("correct-horse-battery-staple")
	if err != nil {
		t.Fatal(err)
	}
	ok, err := policy.Verify(hash, "correct-horse-battery-staple")
	if err != nil || !ok {
		t.Fatalf("verify=%v error=%v", ok, err)
	}
	ok, err = policy.Verify(hash, "wrong-password")
	if err != nil || ok {
		t.Fatalf("wrong password verify=%v error=%v", ok, err)
	}
}
