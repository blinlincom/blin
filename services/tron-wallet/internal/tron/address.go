package tron

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"

	"github.com/btcsuite/btcd/btcec/v2"
	"github.com/btcsuite/btcd/btcutil/base58"
	"github.com/btcsuite/btcd/btcutil/hdkeychain"
	"github.com/btcsuite/btcd/chaincfg"
	"golang.org/x/crypto/sha3"
)

type DerivedAddress struct {
	Address string `json:"address"`
	Hex     string `json:"address_hex"`
	Index   uint32 `json:"index"`
	Path    string `json:"path"`
}

func Derive(seed []byte, appID, userID uint32) (DerivedAddress, error) {
	if len(seed) < 32 {
		return DerivedAddress{}, fmt.Errorf("master seed must contain at least 32 bytes")
	}
	if appID >= hdkeychain.HardenedKeyStart || userID >= hdkeychain.HardenedKeyStart {
		return DerivedAddress{}, fmt.Errorf("derivation index exceeds BIP32 limit")
	}
	key, err := hdkeychain.NewMaster(seed, &chaincfg.MainNetParams)
	if err != nil {
		return DerivedAddress{}, err
	}
	path := []uint32{
		44 + hdkeychain.HardenedKeyStart,
		195 + hdkeychain.HardenedKeyStart,
		appID + hdkeychain.HardenedKeyStart,
		0,
		userID,
	}
	for _, child := range path {
		key, err = key.Derive(child)
		if err != nil {
			return DerivedAddress{}, err
		}
	}
	privateKey, err := key.ECPrivKey()
	if err != nil {
		return DerivedAddress{}, err
	}
	publicKey := privateKey.PubKey().SerializeUncompressed()
	if len(publicKey) != 65 || publicKey[0] != 4 {
		return DerivedAddress{}, fmt.Errorf("unexpected secp256k1 public key")
	}
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write(publicKey[1:])
	digest := hasher.Sum(nil)
	payload := append([]byte{0x41}, digest[len(digest)-20:]...)
	first := sha256.Sum256(payload)
	second := sha256.Sum256(first[:])
	encoded := base58.Encode(append(payload, second[:4]...))
	return DerivedAddress{
		Address: encoded,
		Hex:     hex.EncodeToString(payload),
		Index:   userID,
		Path:    fmt.Sprintf("m/44'/195'/%d'/0/%d", appID, userID),
	}, nil
}

func ParseSeed(value string) ([]byte, error) {
	seed, err := hex.DecodeString(value)
	if err != nil {
		return nil, fmt.Errorf("TRON_MASTER_SEED_HEX is not valid hex: %w", err)
	}
	if len(seed) < 32 {
		return nil, fmt.Errorf("TRON_MASTER_SEED_HEX must contain at least 32 bytes")
	}
	return seed, nil
}

func ValidateAddress(value string) (string, error) {
	decoded := base58.Decode(value)
	if len(decoded) != 25 || decoded[0] != 0x41 {
		return "", fmt.Errorf("invalid TRON address")
	}
	payload := decoded[:21]
	first := sha256.Sum256(payload)
	second := sha256.Sum256(first[:])
	if !bytes.Equal(decoded[21:], second[:4]) {
		return "", fmt.Errorf("invalid TRON address checksum")
	}
	return hex.EncodeToString(payload), nil
}

var _ = btcec.S256
