package wallet

import "testing"

func TestParseAmountIsExact(t *testing.T) {
	for input, expected := range map[string]int64{"0.01": 1, "1": 100, "10.5": 1050, "999999.99": 99999999} {
		actual, err := ParseAmount(input)
		if err != nil || actual != expected {
			t.Fatalf("%s amount=%d err=%v", input, actual, err)
		}
	}
}

func TestParseAmountRejectsPrecisionAndZero(t *testing.T) {
	for _, input := range []string{"0", "0.00", "1.001", "-1", "1e3", ""} {
		if _, err := ParseAmount(input); err == nil {
			t.Fatalf("accepted %q", input)
		}
	}
}
