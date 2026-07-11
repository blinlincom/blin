package main

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"bim/tron-wallet/internal/gasfree"
	"bim/tron-wallet/internal/tron"
)

type gasfreeManagedAccount struct {
	ID             int64  `json:"id"`
	AppID          uint32 `json:"appid"`
	UserID         uint32 `json:"user_id"`
	EOAAddress     string `json:"eoa_address"`
	GasFreeAddress string `json:"gasfree_address"`
	TokenAddress   string `json:"token_address"`
	TokenDecimals  int    `json:"token_decimals"`
}

type gasfreeTask struct {
	ID              int64  `json:"id"`
	AppID           uint32 `json:"appid"`
	UserID          uint32 `json:"user_id"`
	RequestID       string `json:"request_id"`
	EOAAddress      string `json:"eoa_address"`
	GasFreeAddress  string `json:"gasfree_address"`
	ProviderAddress string `json:"provider_address"`
	ReceiverAddress string `json:"receiver_address"`
	TokenAddress    string `json:"token_address"`
	TokenDecimals   int    `json:"token_decimals"`
	Value           string `json:"value"`
	MaxFee          string `json:"max_fee"`
	Nonce           uint64 `json:"nonce"`
	Deadline        uint64 `json:"deadline"`
}

type gasfreeTransferStatus struct {
	ID      int64  `json:"id"`
	TraceID string `json:"trace_id"`
}

func (s *server) gasfreeLoop() {
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	for {
		if err := s.syncGasFreeAccounts(); err != nil {
			logf("gasfree account sync: %v", err)
		}
		if s.gasfreeAuto {
			if err := s.submitGasFreeTask(); err != nil {
				logf("gasfree submit: %v", err)
			}
			if err := s.confirmGasFreeTransfers(); err != nil {
				logf("gasfree confirmation: %v", err)
			}
		}
		<-ticker.C
	}
}

func (s *server) syncGasFreeAccounts() error {
	providers, err := s.gasfreeClient.Providers()
	if err != nil || len(providers) == 0 {
		return fmt.Errorf("provider config unavailable: %w", err)
	}
	tokens, err := s.gasfreeClient.Tokens()
	if err != nil {
		return fmt.Errorf("token config unavailable: %w", err)
	}
	after := int64(0)
	for {
		var response struct {
			Code int    `json:"code"`
			Msg  string `json:"msg"`
			Data struct {
				List []gasfreeManagedAccount `json:"list"`
			} `json:"data"`
		}
		if err := s.callbackCall("/tron/gasfree_accounts", map[string]any{"after_id": after, "limit": 100}, &response); err != nil {
			return err
		}
		if response.Code != 1 {
			return fmt.Errorf("account callback rejected: %s", response.Msg)
		}
		for _, managed := range response.Data.List {
			if err := s.syncGasFreeAccount(managed, providers[0], tokens); err != nil {
				logf("gasfree sync account id=%d: %v", managed.ID, err)
			}
			after = managed.ID
		}
		if len(response.Data.List) < 100 {
			return nil
		}
	}
}

func (s *server) syncGasFreeAccount(managed gasfreeManagedAccount, provider gasfree.Provider, tokens []gasfree.Token) error {
	derived, err := tron.Derive(s.seed, managed.AppID, managed.UserID)
	if err != nil || derived.Address != managed.EOAAddress {
		return fmt.Errorf("derived EOA mismatch")
	}
	account, err := s.gasfreeClient.Account(managed.EOAAddress)
	if err != nil {
		return err
	}
	if account.AccountAddress != managed.EOAAddress || account.GasFreeAddress != managed.GasFreeAddress {
		return fmt.Errorf("provider account identity mismatch")
	}
	var asset gasfree.Asset
	for _, candidate := range account.Assets {
		if candidate.TokenAddress == managed.TokenAddress {
			asset = candidate
			break
		}
	}
	var token gasfree.Token
	for _, candidate := range tokens {
		if candidate.TokenAddress == managed.TokenAddress {
			token = candidate
			break
		}
	}
	if token.TokenAddress == "" || !token.Supported || token.Decimal != managed.TokenDecimals {
		return fmt.Errorf("configured token is not supported")
	}
	balance, err := s.tronClient.TRC20Balance(managed.GasFreeAddress, managed.TokenAddress)
	if err != nil {
		return err
	}
	payload := map[string]any{
		"id": managed.ID, "provider_address": provider.Address, "token_address": managed.TokenAddress,
		"active": account.Active, "allow_submit": account.AllowSubmit, "recommended_nonce": account.Nonce,
		"onchain_balance": unitsDecimal(balance, managed.TokenDecimals),
		"provider_frozen": unitsDecimal(new(big.Int).SetUint64(asset.Frozen), managed.TokenDecimals),
		"activate_fee":    unitsDecimal(new(big.Int).SetUint64(token.ActivateFee), managed.TokenDecimals),
		"transfer_fee":    unitsDecimal(new(big.Int).SetUint64(token.TransferFee), managed.TokenDecimals),
		"decimals":        token.Decimal, "supported": token.Supported, "provider_config": provider.Config,
	}
	var ack callbackResponse
	if err := s.callbackCall("/tron/gasfree_sync", payload, &ack); err != nil {
		return err
	}
	if ack.Code != 1 {
		return fmt.Errorf("sync callback rejected: %s", ack.Msg)
	}
	return nil
}

func (s *server) submitGasFreeTask() error {
	var response struct {
		Code int    `json:"code"`
		Msg  string `json:"msg"`
		Data struct {
			Task *gasfreeTask `json:"task"`
		} `json:"data"`
	}
	if err := s.callbackCall("/tron/gasfree_task", map[string]any{"worker": s.workerID}, &response); err != nil {
		return err
	}
	if response.Code != 1 || response.Data.Task == nil {
		return nil
	}
	task := response.Data.Task
	report := map[string]any{"id": task.ID, "worker": s.workerID}
	transfer, signatureHash, err := s.executeGasFreeTask(*task)
	if err != nil {
		report["success"] = false
		report["error"] = err.Error()
		var apiError *gasfree.APIError
		if errors.As(err, &apiError) {
			report["reason"] = apiError.Reason
		}
	} else {
		report["success"] = true
		report["trace_id"] = transfer.ID
		report["state"] = transfer.State
		report["txn_state"] = transfer.TxnState
		report["signature_hash"] = signatureHash
	}
	var ack callbackResponse
	return s.callbackCall("/tron/gasfree_report", report, &ack)
}

func (s *server) executeGasFreeTask(task gasfreeTask) (gasfree.Transfer, string, error) {
	if task.Deadline <= uint64(time.Now().Unix()+30) {
		return gasfree.Transfer{}, "", fmt.Errorf("gasfree task deadline expired")
	}
	key, derived, err := tron.DerivePrivateKey(s.seed, task.AppID, task.UserID)
	if err != nil || derived.Address != task.EOAAddress {
		return gasfree.Transfer{}, "", fmt.Errorf("derived EOA mismatch")
	}
	value, err := tokenUnits(task.Value, task.TokenDecimals)
	if err != nil || !value.IsUint64() {
		return gasfree.Transfer{}, "", fmt.Errorf("invalid gasfree value")
	}
	maxFee, err := tokenUnits(task.MaxFee, task.TokenDecimals)
	if err != nil || !maxFee.IsUint64() {
		return gasfree.Transfer{}, "", fmt.Errorf("invalid gasfree max fee")
	}
	permit := gasfree.Permit{Token: task.TokenAddress, ServiceProvider: task.ProviderAddress, User: task.EOAAddress, Receiver: task.ReceiverAddress, Value: value, MaxFee: maxFee, Deadline: new(big.Int).SetUint64(task.Deadline), Version: big.NewInt(1), Nonce: new(big.Int).SetUint64(task.Nonce)}
	hash, err := gasfree.PermitHash(s.gasfreeChainID, s.gasfreeController, permit)
	if err != nil {
		return gasfree.Transfer{}, "", err
	}
	signature, err := gasfree.SignPermit(hash, key)
	if err != nil {
		return gasfree.Transfer{}, "", err
	}
	transfer, err := s.gasfreeClient.Submit(gasfree.SubmitRequest{RequestID: task.RequestID, Token: task.TokenAddress, ServiceProvider: task.ProviderAddress, User: task.EOAAddress, Receiver: task.ReceiverAddress, Value: value.Uint64(), MaxFee: maxFee.Uint64(), Deadline: task.Deadline, Version: 1, Nonce: task.Nonce, Sig: signature})
	if err != nil {
		return gasfree.Transfer{}, "", err
	}
	if transfer.AccountAddress != task.EOAAddress || transfer.GasFreeAddress != task.GasFreeAddress || transfer.ProviderAddress != task.ProviderAddress || transfer.TargetAddress != task.ReceiverAddress || transfer.TokenAddress != task.TokenAddress {
		return gasfree.Transfer{}, "", fmt.Errorf("gasfree submit identity mismatch")
	}
	digest := sha256.Sum256([]byte(signature))
	return transfer, hex.EncodeToString(digest[:]), nil
}

func (s *server) confirmGasFreeTransfers() error {
	var response struct {
		Code int    `json:"code"`
		Msg  string `json:"msg"`
		Data struct {
			List []gasfreeTransferStatus `json:"list"`
		} `json:"data"`
	}
	if err := s.callbackCall("/tron/gasfree_confirmations", map[string]any{"limit": 50}, &response); err != nil {
		return err
	}
	for _, pending := range response.Data.List {
		transfer, err := s.gasfreeClient.Transfer(pending.TraceID)
		payload := map[string]any{"id": pending.ID}
		if err != nil {
			payload["error"] = err.Error()
		} else {
			payload["state"] = transfer.State
			payload["txn_state"] = transfer.TxnState
			payload["txn_hash"] = transfer.TxnHash
			payload["txn_amount"] = unitsDecimal(new(big.Int).SetUint64(transfer.TxnAmount), 6)
			payload["txn_total_fee"] = unitsDecimal(new(big.Int).SetUint64(transfer.TxnTotalFee), 6)
		}
		var ack callbackResponse
		if callErr := s.callbackCall("/tron/gasfree_confirm", payload, &ack); callErr != nil {
			logf("gasfree confirmation id=%d callback: %v", pending.ID, callErr)
		}
	}
	return nil
}

func unitsDecimal(value *big.Int, decimals int) string {
	if value == nil || value.Sign() < 0 || decimals < 0 {
		return "0.00000000"
	}
	digits := value.String()
	if decimals > 0 {
		if len(digits) <= decimals {
			digits = strings.Repeat("0", decimals-len(digits)+1) + digits
		}
		digits = digits[:len(digits)-decimals] + "." + digits[len(digits)-decimals:]
	}
	parts := strings.SplitN(digits, ".", 2)
	fraction := ""
	if len(parts) == 2 {
		fraction = parts[1]
	}
	if len(fraction) > 8 {
		fraction = fraction[:8]
	}
	return parts[0] + "." + fraction + strings.Repeat("0", 8-len(fraction))
}
