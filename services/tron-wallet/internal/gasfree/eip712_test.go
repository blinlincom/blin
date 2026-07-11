package gasfree

import (
	"encoding/hex"
	"math/big"
	"testing"
)

func TestPermitHashVector(t *testing.T) {
	p := Permit{Token: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t", ServiceProvider: "TWjeEDscpdbrNihP9KTYDrW95cAT6TVLDs", User: "TV41sgpeZAaWJMGbn43AySVUdQEx4j6Yv4", Receiver: "TNeAJs2R4KyYrseRhdFHashQd8dV6NSKDQ", Value: big.NewInt(100000000), MaxFee: big.NewInt(3000000), Deadline: big.NewInt(2000000000), Version: big.NewInt(1), Nonce: big.NewInt(7)}
	h, err := PermitHash(728126428, "TFFAMQLZybALaLb4uxHA9RBE7pxhUAjF3U", p)
	if err != nil {
		t.Fatal(err)
	}
	const expected = "3ee467fbb452394ad8cff825c9c9738c4d0fe28e9bdb23c4f3a6fe1e350c20d7"
	if actual := hex.EncodeToString(h); actual != expected {
		t.Fatalf("permit hash mismatch: got %s want %s", actual, expected)
	}
}
