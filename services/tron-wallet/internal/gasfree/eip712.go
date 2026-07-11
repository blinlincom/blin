package gasfree

import (
	"encoding/hex"
	"fmt"
	"math/big"

	"bim/tron-wallet/internal/tron"
	"github.com/btcsuite/btcd/btcec/v2"
	"github.com/btcsuite/btcd/btcec/v2/ecdsa"
	"golang.org/x/crypto/sha3"
)

const domainType = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
const permitType = "PermitTransfer(address token,address serviceProvider,address user,address receiver,uint256 value,uint256 maxFee,uint256 deadline,uint256 version,uint256 nonce)"

type Permit struct {
	Token, ServiceProvider, User, Receiver  string
	Value, MaxFee, Deadline, Version, Nonce *big.Int
}

func PermitHash(chainID uint64, controller string, p Permit) ([]byte, error) {
	domainAddress, err := addressWord(controller)
	if err != nil {
		return nil, err
	}
	domain := hashWords(hashString(domainType), hashString("GasFreeController"), hashString("V1.0.0"), uintWord(new(big.Int).SetUint64(chainID)), domainAddress)
	addresses := make([][]byte, 4)
	for i, v := range []string{p.Token, p.ServiceProvider, p.User, p.Receiver} {
		addresses[i], err = addressWord(v)
		if err != nil {
			return nil, err
		}
	}
	for _, n := range []*big.Int{p.Value, p.MaxFee, p.Deadline, p.Version, p.Nonce} {
		if n == nil || n.Sign() < 0 {
			return nil, fmt.Errorf("invalid permit number")
		}
	}
	message := hashWords(hashString(permitType), addresses[0], addresses[1], addresses[2], addresses[3], uintWord(p.Value), uintWord(p.MaxFee), uintWord(p.Deadline), uintWord(p.Version), uintWord(p.Nonce))
	return keccak(append(append([]byte{0x19, 0x01}, domain...), message...)), nil
}

func SignPermit(hash []byte, key *btcec.PrivateKey) (string, error) {
	if len(hash) != 32 {
		return "", fmt.Errorf("invalid permit hash")
	}
	compact := ecdsa.SignCompact(key, hash, false)
	if len(compact) != 65 {
		return "", fmt.Errorf("invalid signature")
	}
	v := compact[0]
	sig := append(append([]byte{}, compact[1:]...), v)
	return "0x" + hex.EncodeToString(sig), nil
}
func hashString(s string) []byte { return keccak([]byte(s)) }
func hashWords(words ...[]byte) []byte {
	var b []byte
	for _, w := range words {
		b = append(b, w...)
	}
	return keccak(b)
}
func keccak(b []byte) []byte { h := sha3.NewLegacyKeccak256(); _, _ = h.Write(b); return h.Sum(nil) }
func uintWord(n *big.Int) []byte {
	out := make([]byte, 32)
	b := n.Bytes()
	copy(out[32-len(b):], b)
	return out
}
func addressWord(value string) ([]byte, error) {
	h, err := tron.ValidateAddress(value)
	if err != nil {
		return nil, err
	}
	raw, err := hex.DecodeString(h)
	if err != nil || len(raw) != 21 {
		return nil, fmt.Errorf("invalid address")
	}
	out := make([]byte, 32)
	copy(out[12:], raw[1:])
	return out, nil
}
