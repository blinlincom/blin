package main

import (
	"fmt"
	"math/big"
	"os"
	"strconv"
	"strings"
	"time"

	"bim/tron-wallet/internal/tron"
	"github.com/btcsuite/btcd/btcec/v2"
)

type chainTask struct {
	ID        int64  `json:"id"`
	Kind      string `json:"kind"`
	AppID     uint32 `json:"appid"`
	UserID    uint32 `json:"user_id"`
	AddressID int64  `json:"address_id"`
	From      string `json:"from_address"`
	To        string `json:"to_address"`
	Contract  string `json:"contract_address"`
	Amount    string `json:"amount"`
	Decimals  int    `json:"decimals"`
	TxID      string `json:"txid"`
}
type taskResponse struct {
	Code int    `json:"code"`
	Msg  string `json:"msg"`
	Data struct {
		Task *chainTask `json:"task"`
	} `json:"data"`
}

func (s *server) workerLoop() {
	ticker := time.NewTicker(8 * time.Second)
	defer ticker.Stop()
	for {
		if err := s.confirmOnce(); err != nil {
			logf("confirmation worker: %v", err)
		}
		if err := s.workOnce(); err != nil {
			logf("wallet worker: %v", err)
		}
		<-ticker.C
	}
}
func (s *server) confirmOnce() error {
	var r taskResponse
	if err := s.callbackCall("/tron/confirm_task", map[string]any{"worker": s.workerID}, &r); err != nil {
		return err
	}
	if r.Code != 1 || r.Data.Task == nil {
		return nil
	}
	t := r.Data.Task
	confirmed, success, err := s.tronClient.Confirmed(t.TxID)
	payload := map[string]any{"id": t.ID, "kind": t.Kind, "worker": s.workerID, "confirmed": confirmed, "success": success}
	if err != nil {
		payload["error"] = err.Error()
	}
	var ack callbackResponse
	return s.callbackCall("/tron/confirm_report", payload, &ack)
}
func (s *server) workOnce() error {
	var r taskResponse
	if err := s.callbackCall("/tron/task", map[string]any{"worker": s.workerID}, &r); err != nil {
		return err
	}
	if r.Code != 1 || r.Data.Task == nil {
		return nil
	}
	t := r.Data.Task
	txid, broadcasted, err := s.executeTask(*t)
	payload := map[string]any{"id": t.ID, "kind": t.Kind, "worker": s.workerID, "success": broadcasted, "txid": txid}
	if err != nil {
		payload["error"] = err.Error()
	}
	var ack callbackResponse
	return s.callbackCall("/tron/task_report", payload, &ack)
}
func (s *server) executeTask(t chainTask) (string, bool, error) {
	amount, err := tokenUnits(t.Amount, t.Decimals)
	if err != nil {
		return "", false, err
	}
	var key *btcec.PrivateKey
	var owner string
	if t.Kind == "sweep" {
		k, a, e := tron.DerivePrivateKey(s.seed, t.AppID, t.UserID)
		if e != nil {
			return "", false, e
		}
		if a.Address != t.From {
			return "", false, fmt.Errorf("derived address mismatch")
		}
		key, owner = k, a.Address
		if s.resourceKey != nil && s.resourceTopupSun > 0 {
			if e = s.ensureTRX(owner); e != nil {
				return "", false, e
			}
		}
	} else if t.Kind == "withdraw" {
		if s.hotKey == nil {
			return "", false, fmt.Errorf("withdraw hot wallet not configured")
		}
		key, owner = s.hotKey, s.hotAddress
	} else {
		return "", false, fmt.Errorf("unsupported task")
	}
	tx, e := s.tronClient.TriggerTRC20(owner, t.Contract, t.To, amount)
	if e != nil {
		return "", false, e
	}
	if e = tron.Sign(tx, key); e != nil {
		return tx.TxID, false, e
	}
	id, e := s.tronClient.Broadcast(tx)
	if e != nil {
		return tx.TxID, false, e
	}
	return id, true, nil
}
func (s *server) ensureTRX(to string) error {
	balance, err := s.tronClient.TRXBalance(to)
	if err != nil {
		return err
	}
	missing := s.resourceTopupSun - balance
	if missing <= 0 {
		return nil
	}
	tx, err := s.tronClient.TransferTRX(s.resourceAddress, to, missing)
	if err != nil {
		return err
	}
	if err = tron.Sign(tx, s.resourceKey); err != nil {
		return err
	}
	id, err := s.tronClient.Broadcast(tx)
	if err != nil {
		return err
	}
	deadline := time.Now().Add(90 * time.Second)
	for time.Now().Before(deadline) {
		confirmed, ok, e := s.tronClient.Confirmed(id)
		if e == nil && confirmed {
			if ok {
				return nil
			}
			return fmt.Errorf("resource transaction failed")
		}
		time.Sleep(3 * time.Second)
	}
	return fmt.Errorf("resource transaction confirmation timeout")
}
func tokenUnits(value string, decimals int) (*big.Int, error) {
	if decimals < 0 || decimals > 18 {
		return nil, fmt.Errorf("invalid decimals")
	}
	parts := strings.Split(value, ".")
	if len(parts) > 2 {
		return nil, fmt.Errorf("invalid amount")
	}
	whole := parts[0]
	frac := ""
	if len(parts) == 2 {
		frac = parts[1]
	}
	if whole == "" {
		whole = "0"
	}
	if len(frac) > decimals {
		return nil, fmt.Errorf("amount precision exceeds token decimals")
	}
	frac += strings.Repeat("0", decimals-len(frac))
	n, ok := new(big.Int).SetString(whole+frac, 10)
	if !ok || n.Sign() <= 0 {
		return nil, fmt.Errorf("invalid amount")
	}
	return n, nil
}
func parsePrivateEnv(name string) (tron.DerivedAddress, *btcec.PrivateKey, error) {
	v := strings.TrimSpace(os.Getenv(name))
	if v == "" {
		return tron.DerivedAddress{}, nil, nil
	}
	return tron.AddressFromPrivateHex(v)
}
func envInt64(name string, def int64) int64 {
	v, _ := strconv.ParseInt(strings.TrimSpace(os.Getenv(name)), 10, 64)
	if v <= 0 {
		return def
	}
	return v
}
func logf(format string, args ...any) {
	fmt.Printf(time.Now().Format(time.RFC3339)+" "+format+"\n", args...)
}
