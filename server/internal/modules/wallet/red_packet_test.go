package wallet

import "testing"

func TestNormalPacketDistributesAllCents(t *testing.T) {
	remaining, count, sum := int64(100), uint32(3), int64(0)
	for count > 0 {
		amount, err := claimAmount("normal", remaining, count)
		if err != nil {
			t.Fatal(err)
		}
		sum += amount
		remaining -= amount
		count--
	}
	if sum != 100 || remaining != 0 {
		t.Fatalf("sum=%d remaining=%d", sum, remaining)
	}
}

func TestLuckyPacketLeavesOneCentPerRecipient(t *testing.T) {
	for i := 0; i < 100; i++ {
		amount, err := claimAmount("lucky", 100, 10)
		if err != nil {
			t.Fatal(err)
		}
		if amount < 1 || 100-amount < 9 {
			t.Fatalf("amount=%d", amount)
		}
	}
}
