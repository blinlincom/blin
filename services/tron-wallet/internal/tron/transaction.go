package tron

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strings"

	"github.com/btcsuite/btcd/btcec/v2"
	"github.com/btcsuite/btcd/btcec/v2/ecdsa"
)

type Client struct {
	BaseURL, APIKey string
	HTTP            *http.Client
}

func (c Client) Call(path string, payload any, out any) error {
	b, _ := json.Marshal(payload)
	req, _ := http.NewRequest(http.MethodPost, strings.TrimRight(c.BaseURL, "/")+path, bytes.NewReader(b))
	req.Header.Set("Content-Type", "application/json")
	if c.APIKey != "" {
		req.Header.Set("TRON-PRO-API-KEY", c.APIKey)
	}
	res, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if res.StatusCode/100 != 2 {
		return fmt.Errorf("tron status %d: %s", res.StatusCode, string(raw))
	}
	if err = json.Unmarshal(raw, out); err != nil {
		return err
	}
	return nil
}

type Transaction struct {
	TxID       string   `json:"txID"`
	RawDataHex string   `json:"raw_data_hex"`
	RawData    any      `json:"raw_data"`
	Signature  []string `json:"signature,omitempty"`
	Visible    bool     `json:"visible,omitempty"`
}

func Sign(tx *Transaction, key *btcec.PrivateKey) error {
	raw, err := hex.DecodeString(tx.RawDataHex)
	if err != nil {
		return err
	}
	h := sha256.Sum256(raw)
	compact := ecdsa.SignCompact(key, h[:], false)
	if len(compact) != 65 {
		return fmt.Errorf("bad compact signature")
	}
	rec := compact[0] - 27
	sig := append(append([]byte{}, compact[1:]...), rec)
	tx.Signature = []string{hex.EncodeToString(sig)}
	if tx.TxID == "" {
		tx.TxID = hex.EncodeToString(h[:])
	}
	return nil
}
func (c Client) TriggerTRC20(owner, contract, to string, amount *big.Int) (*Transaction, error) {
	ownerHex, err := ValidateAddress(owner)
	if err != nil {
		return nil, fmt.Errorf("invalid owner address: %w", err)
	}
	contractHex, err := ValidateAddress(contract)
	if err != nil {
		return nil, fmt.Errorf("invalid contract address: %w", err)
	}
	toHex, err := ValidateAddress(to)
	if err != nil {
		return nil, fmt.Errorf("invalid target address: %w", err)
	}
	param := fmt.Sprintf("%064s%064s", strings.TrimPrefix(toHex, "41"), amount.Text(16))
	var out struct {
		Result struct {
			Result  bool   `json:"result"`
			Message string `json:"message"`
		} `json:"result"`
		Transaction Transaction `json:"transaction"`
	}
	err = c.Call("/wallet/triggersmartcontract", map[string]any{"owner_address": ownerHex, "contract_address": contractHex, "function_selector": "transfer(address,uint256)", "parameter": param, "fee_limit": 150000000, "call_value": 0, "visible": false}, &out)
	if err != nil {
		return nil, err
	}
	if !out.Result.Result {
		return nil, fmt.Errorf("trigger failed: %s", out.Result.Message)
	}
	return &out.Transaction, nil
}

func (c Client) TRXBalance(address string) (int64, error) {
	var out struct {
		Balance int64 `json:"balance"`
	}
	if err := c.Call("/wallet/getaccount", map[string]any{"address": address, "visible": true}, &out); err != nil {
		return 0, err
	}
	return out.Balance, nil
}

func (c Client) TRC20Balance(owner, contract string) (*big.Int, error) {
	ownerHex, err := ValidateAddress(owner)
	if err != nil {
		return nil, err
	}
	contractHex, err := ValidateAddress(contract)
	if err != nil {
		return nil, err
	}
	param := fmt.Sprintf("%064s", strings.TrimPrefix(ownerHex, "41"))
	var out struct {
		Result struct {
			Result  bool   `json:"result"`
			Message string `json:"message"`
		} `json:"result"`
		ConstantResult []string `json:"constant_result"`
	}
	if err = c.Call("/wallet/triggerconstantcontract", map[string]any{"owner_address": ownerHex, "contract_address": contractHex, "function_selector": "balanceOf(address)", "parameter": param, "visible": false}, &out); err != nil {
		return nil, err
	}
	if !out.Result.Result || len(out.ConstantResult) == 0 {
		return nil, fmt.Errorf("balance query failed: %s", out.Result.Message)
	}
	hexValue := strings.TrimLeft(out.ConstantResult[0], "0")
	if hexValue == "" {
		return big.NewInt(0), nil
	}
	n, ok := new(big.Int).SetString(hexValue, 16)
	if !ok {
		return nil, fmt.Errorf("invalid token balance")
	}
	return n, nil
}
func (c Client) TransferTRX(owner, to string, sun int64) (*Transaction, error) {
	var tx Transaction
	err := c.Call("/wallet/createtransaction", map[string]any{"owner_address": owner, "to_address": to, "amount": sun, "visible": true}, &tx)
	return &tx, err
}
func (c Client) Broadcast(tx *Transaction) (string, error) {
	var out struct {
		Result  bool   `json:"result"`
		Code    string `json:"code"`
		Message string `json:"message"`
		TxID    string `json:"txid"`
	}
	if err := c.Call("/wallet/broadcasttransaction", tx, &out); err != nil {
		return "", err
	}
	if !out.Result {
		return "", fmt.Errorf("broadcast %s: %s", out.Code, out.Message)
	}
	if out.TxID != "" {
		return out.TxID, nil
	}
	return tx.TxID, nil
}
func (c Client) Confirmed(txid string) (bool, bool, error) {
	var out struct {
		ID      string `json:"id"`
		Receipt struct {
			Result string `json:"result"`
		} `json:"receipt"`
		Result string `json:"result"`
	}
	if err := c.Call("/walletsolidity/gettransactioninfobyid", map[string]any{"value": txid}, &out); err != nil {
		return false, false, err
	}
	if out.ID == "" {
		return false, false, nil
	}
	ok := out.Receipt.Result == "SUCCESS" || out.Result == "SUCCESS"
	return true, ok, nil
}
