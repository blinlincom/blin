package gasfree

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

const maxResponseBytes = 1 << 20

type Client struct {
	BaseURL, APIKey, APISecret string
	HTTP                       *http.Client
}

type Account struct {
	AccountAddress string  `json:"accountAddress"`
	GasFreeAddress string  `json:"gasFreeAddress"`
	Active         bool    `json:"active"`
	Nonce          uint64  `json:"nonce"`
	AllowSubmit    bool    `json:"-"`
	Assets         []Asset `json:"assets"`
}

func (a *Account) UnmarshalJSON(data []byte) error {
	type accountAlias Account
	var raw struct {
		accountAlias
		AllowSubmitCamel *bool `json:"allowSubmit"`
		AllowSubmitSnake *bool `json:"allow_submit"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	*a = Account(raw.accountAlias)
	if raw.AllowSubmitSnake != nil {
		a.AllowSubmit = *raw.AllowSubmitSnake
	} else if raw.AllowSubmitCamel != nil {
		a.AllowSubmit = *raw.AllowSubmitCamel
	}
	return nil
}

type Asset struct {
	TokenAddress string `json:"tokenAddress"`
	TokenSymbol  string `json:"tokenSymbol"`
	ActivateFee  uint64 `json:"activateFee"`
	TransferFee  uint64 `json:"transferFee"`
	Decimal      int    `json:"decimal"`
	Frozen       uint64 `json:"frozen"`
}

type Token struct {
	TokenAddress string `json:"tokenAddress"`
	ActivateFee  uint64 `json:"activateFee"`
	TransferFee  uint64 `json:"transferFee"`
	Supported    bool   `json:"supported"`
	Symbol       string `json:"symbol"`
	Decimal      int    `json:"decimal"`
}

type Provider struct {
	Address string         `json:"address"`
	Name    string         `json:"name"`
	Config  ProviderConfig `json:"config"`
}

type ProviderConfig struct {
	MaxPendingTransfer      int    `json:"maxPendingTransfer"`
	MinDeadlineDuration     uint64 `json:"minDeadlineDuration"`
	MaxDeadlineDuration     uint64 `json:"maxDeadlineDuration"`
	DefaultDeadlineDuration uint64 `json:"defaultDeadlineDuration"`
}

type Envelope[T any] struct {
	Code    int    `json:"code"`
	Reason  string `json:"reason"`
	Message string `json:"message"`
	Data    T      `json:"data"`
}

type SubmitRequest struct {
	RequestID, Token, ServiceProvider, User, Receiver string
	Value, MaxFee, Deadline, Version, Nonce           uint64
	Sig                                               string
}

type Transfer struct {
	ID                   string `json:"id"`
	AccountAddress       string `json:"accountAddress"`
	GasFreeAddress       string `json:"gasFreeAddress"`
	ProviderAddress      string `json:"providerAddress"`
	TargetAddress        string `json:"targetAddress"`
	TokenAddress         string `json:"tokenAddress"`
	State                string `json:"state"`
	TxnState             string `json:"txnState"`
	TxnHash              string `json:"txnHash"`
	Amount               uint64 `json:"amount"`
	MaxFee               uint64 `json:"maxFee"`
	EstimatedActivateFee uint64 `json:"estimatedActivateFee"`
	EstimatedTransferFee uint64 `json:"estimatedTransferFee"`
	EstimatedTotalFee    uint64 `json:"estimatedTotalFee"`
	TxnAmount            uint64 `json:"txnAmount"`
	TxnTotalFee          uint64 `json:"txnTotalFee"`
	Nonce                uint64 `json:"nonce"`
}

type APIError struct {
	Code, Status int
	Reason, Msg  string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("gasfree rejected code=%d reason=%s message=%s", e.Code, e.Reason, e.Msg)
}

func (c Client) Ready() bool {
	return c.BaseURL != "" && c.APIKey != "" && c.APISecret != "" && c.HTTP != nil
}

func (c Client) request(method, path string, payload any, out any) error {
	if !c.Ready() {
		return fmt.Errorf("gasfree credentials not configured")
	}
	if !strings.HasPrefix(path, "/api/") {
		return fmt.Errorf("invalid gasfree path")
	}
	base, err := url.Parse(strings.TrimRight(c.BaseURL, "/"))
	if err != nil || base.Scheme != "https" || base.Host == "" {
		return fmt.Errorf("gasfree API URL must be HTTPS")
	}
	var body []byte
	if payload != nil {
		body, err = json.Marshal(payload)
		if err != nil {
			return err
		}
	}
	ts := strconv.FormatInt(time.Now().UnixMilli(), 10)
	mac := hmac.New(sha256.New, []byte(c.APISecret))
	_, _ = mac.Write([]byte(method + path + ts))
	req, err := http.NewRequest(method, strings.TrimRight(c.BaseURL, "/")+path, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Timestamp", ts)
	req.Header.Set("Authorization", "ApiKey "+c.APIKey+":"+base64.StdEncoding.EncodeToString(mac.Sum(nil)))
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	res, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	raw, err := io.ReadAll(io.LimitReader(res.Body, maxResponseBytes+1))
	if err != nil {
		return err
	}
	if len(raw) > maxResponseBytes {
		return fmt.Errorf("gasfree response too large")
	}
	if res.StatusCode/100 != 2 {
		return &APIError{Status: res.StatusCode, Msg: "unexpected HTTP status"}
	}
	if err = json.Unmarshal(raw, out); err != nil {
		return fmt.Errorf("invalid gasfree response: %w", err)
	}
	return nil
}

func (c Client) Account(address string) (Account, error) {
	var result Envelope[Account]
	if err := c.request(http.MethodGet, "/api/v1/address/"+url.PathEscape(address), nil, &result); err != nil {
		return Account{}, err
	}
	if result.Code != http.StatusOK {
		return Account{}, &APIError{Code: result.Code, Reason: result.Reason, Msg: result.Message}
	}
	if result.Data.AccountAddress == "" || result.Data.GasFreeAddress == "" {
		return Account{}, fmt.Errorf("gasfree account response incomplete")
	}
	return result.Data, nil
}

func (c Client) Tokens() ([]Token, error) {
	var result Envelope[struct {
		Tokens []Token `json:"tokens"`
	}]
	if err := c.request(http.MethodGet, "/api/v1/config/token/all", nil, &result); err != nil {
		return nil, err
	}
	if result.Code != http.StatusOK {
		return nil, &APIError{Code: result.Code, Reason: result.Reason, Msg: result.Message}
	}
	return result.Data.Tokens, nil
}

func (c Client) Providers() ([]Provider, error) {
	var result Envelope[struct {
		Providers []Provider `json:"providers"`
	}]
	if err := c.request(http.MethodGet, "/api/v1/config/provider/all", nil, &result); err != nil {
		return nil, err
	}
	if result.Code != http.StatusOK {
		return nil, &APIError{Code: result.Code, Reason: result.Reason, Msg: result.Message}
	}
	return result.Data.Providers, nil
}

func (c Client) Submit(r SubmitRequest) (Transfer, error) {
	payload := map[string]any{
		"requestId": r.RequestID, "token": r.Token, "serviceProvider": r.ServiceProvider,
		"user": r.User, "receiver": r.Receiver, "value": r.Value, "maxFee": r.MaxFee,
		"deadline": r.Deadline, "version": r.Version, "nonce": r.Nonce,
		"sig": strings.TrimPrefix(r.Sig, "0x"),
	}
	var result Envelope[Transfer]
	if err := c.request(http.MethodPost, "/api/v1/gasfree/submit", payload, &result); err != nil {
		return Transfer{}, err
	}
	if result.Code != http.StatusOK {
		return Transfer{}, &APIError{Code: result.Code, Reason: result.Reason, Msg: result.Message}
	}
	if result.Data.ID == "" {
		return Transfer{}, fmt.Errorf("gasfree trace id missing")
	}
	return result.Data, nil
}

func (c Client) Transfer(id string) (Transfer, error) {
	var result Envelope[Transfer]
	if err := c.request(http.MethodGet, "/api/v1/gasfree/"+url.PathEscape(id), nil, &result); err != nil {
		return Transfer{}, err
	}
	if result.Code != http.StatusOK {
		return Transfer{}, &APIError{Code: result.Code, Reason: result.Reason, Msg: result.Message}
	}
	return result.Data, nil
}
