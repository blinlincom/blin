package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"bim/tron-wallet/internal/gasfree"
	"bim/tron-wallet/internal/tron"
	"github.com/btcsuite/btcd/btcec/v2"
)

type server struct {
	secret            string
	seed              []byte
	tronAPI           string
	apiKey            string
	callback          string
	client            *http.Client
	tronClient        tron.Client
	workerID          string
	resourceKey       *btcec.PrivateKey
	resourceAddress   string
	resourceTopupSun  int64
	hotKey            *btcec.PrivateKey
	hotAddress        string
	chainWorker       bool
	gasfreeClient     gasfree.Client
	gasfreeEnabled    bool
	gasfreeAuto       bool
	gasfreeChainID    uint64
	gasfreeController string
}

type deriveRequest struct {
	AppID  uint32 `json:"appid"`
	UserID uint32 `json:"user_id"`
}

type validateRequest struct {
	Address string `json:"address"`
}
type gasfreeAccountRequest struct {
	AppID  uint32 `json:"appid"`
	UserID uint32 `json:"user_id"`
}

func main() {
	listen := env("TRON_WALLET_LISTEN", "127.0.0.1:9088")
	secret := strings.TrimSpace(os.Getenv("TRON_INTERNAL_SECRET"))
	if len(secret) < 32 {
		log.Fatal("TRON_INTERNAL_SECRET must contain at least 32 characters")
	}
	var seed []byte
	if raw := strings.TrimSpace(os.Getenv("TRON_MASTER_SEED_HEX")); raw != "" {
		parsed, err := tron.ParseSeed(raw)
		if err != nil {
			log.Fatal(err)
		}
		seed = parsed
	}
	client := &http.Client{Timeout: 12 * time.Second}
	fullnode := strings.TrimRight(env("TRON_FULLNODE_URL", "https://api.trongrid.io"), "/")
	resourceAddress, resourceKey, err := parsePrivateEnv("TRON_RESOURCE_PRIVATE_KEY")
	if err != nil {
		log.Fatal(err)
	}
	hotAddress, hotKey, err := parsePrivateEnv("TRON_WITHDRAW_HOT_PRIVATE_KEY")
	if err != nil {
		log.Fatal(err)
	}
	chainWorker := strings.EqualFold(env("TRON_CHAIN_WORKER_ENABLED", "false"), "true")
	gasfreeEnabled := strings.EqualFold(env("TRON_GASFREE_ENABLED", "false"), "true")
	gasfreeAuto := strings.EqualFold(env("TRON_GASFREE_AUTO_ENABLED", "false"), "true")
	gasfreeChainID, err := strconv.ParseUint(env("TRON_GASFREE_CHAIN_ID", "728126428"), 10, 64)
	if err != nil || gasfreeChainID == 0 {
		log.Fatal("TRON_GASFREE_CHAIN_ID is invalid")
	}
	gasfreeController := strings.TrimSpace(env("TRON_GASFREE_VERIFYING_CONTRACT", "TFFAMQLZybALaLb4uxHA9RBE7pxhUAjF3U"))
	if _, err = tron.ValidateAddress(gasfreeController); err != nil {
		log.Fatal("TRON_GASFREE_VERIFYING_CONTRACT is invalid")
	}
	gasfreeClient := gasfree.Client{BaseURL: strings.TrimRight(strings.TrimSpace(os.Getenv("TRON_GASFREE_API_URL")), "/"), APIKey: strings.TrimSpace(os.Getenv("TRON_GASFREE_API_KEY")), APISecret: strings.TrimSpace(os.Getenv("TRON_GASFREE_API_SECRET")), HTTP: client}
	if gasfreeEnabled && (!gasfreeClient.Ready() || len(seed) == 0) {
		log.Fatal("GasFree enabled without credentials or master seed")
	}
	s := &server{secret: secret, seed: seed, tronAPI: strings.TrimRight(env("TRON_EVENT_API_URL", "https://api.trongrid.io"), "/"), apiKey: strings.TrimSpace(os.Getenv("TRON_API_KEY")), callback: strings.TrimRight(strings.TrimSpace(os.Getenv("TRON_CALLBACK_URL")), "/"), client: client, tronClient: tron.Client{BaseURL: fullnode, APIKey: strings.TrimSpace(os.Getenv("TRON_API_KEY")), HTTP: client}, workerID: env("TRON_WORKER_ID", "wallet-1"), resourceKey: resourceKey, resourceAddress: resourceAddress.Address, resourceTopupSun: envInt64("TRON_RESOURCE_TOPUP_SUN", 30000000), hotKey: hotKey, hotAddress: hotAddress.Address, chainWorker: chainWorker, gasfreeClient: gasfreeClient, gasfreeEnabled: gasfreeEnabled, gasfreeAuto: gasfreeAuto, gasfreeChainID: gasfreeChainID, gasfreeController: gasfreeController}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", s.health)
	mux.HandleFunc("POST /internal/address/derive", s.auth(s.derive))
	mux.HandleFunc("POST /internal/address/validate", s.auth(s.validate))
	mux.HandleFunc("POST /internal/gasfree/account", s.auth(s.gasfreeAccount))
	httpServer := &http.Server{
		Addr:              listen,
		Handler:           requestLimit(mux),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       8 * time.Second,
		WriteTimeout:      8 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	log.Printf("tron wallet service listening on %s (legacy address generation disabled, gasfree enabled=%t)", listen, gasfreeEnabled)
	if s.callback != "" {
		go s.scanLoop()
		if s.chainWorker {
			go s.workerLoop()
		}
		if s.gasfreeEnabled {
			go s.gasfreeLoop()
		}
	} else {
		log.Printf("deposit scanner disabled: TRON_CALLBACK_URL is empty")
	}
	log.Fatal(httpServer.ListenAndServe())
}

type managedAddress struct {
	ID        int64  `json:"id"`
	NetworkID int    `json:"network_id"`
	Address   string `json:"address_base58"`
	Contract  string `json:"contract_address"`
	Decimals  int    `json:"decimals"`
}
type callbackResponse struct {
	Code int    `json:"code"`
	Msg  string `json:"msg"`
	Data struct {
		List []managedAddress `json:"list"`
	} `json:"data"`
}
type eventPage struct {
	Data []struct {
		TransactionID  string         `json:"transaction_id"`
		BlockNumber    int64          `json:"block_number"`
		EventIndex     int            `json:"event_index"`
		BlockTimestamp int64          `json:"block_timestamp"`
		Result         map[string]any `json:"result"`
	} `json:"data"`
}

func (s *server) scanLoop() {
	ticker := time.NewTicker(20 * time.Second)
	defer ticker.Stop()
	for {
		if err := s.scanOnce(); err != nil {
			log.Printf("deposit scan failed: %v", err)
		}
		<-ticker.C
	}
}

func (s *server) scanOnce() error {
	after := int64(0)
	for {
		var addresses callbackResponse
		if err := s.callbackCall("/tron/addresses", map[string]any{"after_id": after, "limit": 200}, &addresses); err != nil {
			return err
		}
		if addresses.Code != 1 {
			return fmt.Errorf("address callback rejected: %s", addresses.Msg)
		}
		if len(addresses.Data.List) == 0 {
			return nil
		}
		for _, item := range addresses.Data.List {
			if err := s.scanAddress(item); err != nil {
				log.Printf("scan address id=%d failed: %v", item.ID, err)
			}
			after = item.ID
		}
		if len(addresses.Data.List) < 200 {
			return nil
		}
	}
}

func (s *server) scanAddress(item managedAddress) error {
	if item.Address == "" || item.Contract == "" {
		return nil
	}
	endpoint := fmt.Sprintf("%s/v1/accounts/%s/transactions/trc20?only_confirmed=true&only_to=true&contract_address=%s&limit=200&order_by=block_timestamp,desc", s.tronAPI, url.PathEscape(item.Address), url.QueryEscape(item.Contract))
	req, _ := http.NewRequest(http.MethodGet, endpoint, nil)
	if s.apiKey != "" {
		req.Header.Set("TRON-PRO-API-KEY", s.apiKey)
	}
	response, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("tron api status %d", response.StatusCode)
	}
	var page struct {
		Data []struct {
			TransactionID  string `json:"transaction_id"`
			EventIndex     int    `json:"event_index"`
			BlockTimestamp int64  `json:"block_timestamp"`
			From           string `json:"from"`
			To             string `json:"to"`
			Value          string `json:"value"`
			TokenInfo      struct {
				Address  string `json:"address"`
				Decimals int    `json:"decimals"`
			} `json:"token_info"`
		} `json:"data"`
	}
	if err := json.NewDecoder(response.Body).Decode(&page); err != nil {
		return err
	}
	for _, event := range page.Data {
		if event.To != item.Address || event.TokenInfo.Address != item.Contract {
			continue
		}
		amount, err := decimalUnits(event.Value, event.TokenInfo.Decimals)
		if err != nil {
			continue
		}
		payload := map[string]any{"network_id": item.NetworkID, "contract_address": item.Contract, "block_number": 0, "block_timestamp": event.BlockTimestamp, "txid": event.TransactionID, "log_index": event.EventIndex, "from_address": event.From, "to_address": event.To, "amount": amount}
		var result callbackResponse
		if err := s.callbackCall("/tron/deposit", payload, &result); err != nil {
			return err
		}
		if result.Code != 1 {
			return fmt.Errorf("deposit callback rejected: %s", result.Msg)
		}
	}
	return nil
}

func decimalUnits(value string, decimals int) (string, error) {
	if decimals < 0 || decimals > 18 {
		return "", fmt.Errorf("invalid decimals")
	}
	value = strings.TrimLeft(value, "0")
	if value == "" {
		value = "0"
	}
	if decimals == 0 {
		return value + ".00000000", nil
	}
	if len(value) <= decimals {
		value = strings.Repeat("0", decimals-len(value)+1) + value
	}
	point := len(value) - decimals
	fraction := value[point:]
	if len(fraction) > 8 {
		fraction = fraction[:8]
	} else {
		fraction += strings.Repeat("0", 8-len(fraction))
	}
	return value[:point] + "." + fraction, nil
}

func (s *server) callbackCall(path string, payload any, target any) error {
	body, _ := json.Marshal(payload)
	timestamp := strconv.FormatInt(time.Now().Unix(), 10)
	mac := hmac.New(sha256.New, []byte(s.secret))
	_, _ = fmt.Fprintf(mac, "%s\n%s", timestamp, body)
	req, err := http.NewRequest(http.MethodPost, s.callback+path, strings.NewReader(string(body)))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-BIM-Timestamp", timestamp)
	req.Header.Set("X-BIM-Signature", hex.EncodeToString(mac.Sum(nil)))
	response, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("callback status %d", response.StatusCode)
	}
	return json.NewDecoder(response.Body).Decode(target)
}

func (s *server) validate(w http.ResponseWriter, r *http.Request, body []byte) {
	var request validateRequest
	if err := json.Unmarshal(body, &request); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid validate request"})
		return
	}
	hexAddress, err := tron.ValidateAddress(strings.TrimSpace(request.Address))
	if err != nil {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]any{"valid": false, "error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"valid": true, "address_hex": hexAddress})
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":                         true,
		"legacy_address_generation":  false,
		"chain_worker_enabled":       s.chainWorker,
		"resource_wallet_configured": s.resourceKey != nil,
		"withdraw_wallet_configured": s.hotKey != nil,
		"resource_address":           s.resourceAddress,
		"withdraw_address":           s.hotAddress,
		"gasfree_enabled":            s.gasfreeEnabled,
		"gasfree_credentials_ready":  s.gasfreeClient.Ready(),
		"gasfree_auto_enabled":       s.gasfreeAuto,
	})
}

func (s *server) derive(w http.ResponseWriter, r *http.Request, body []byte) {
	writeJSON(w, http.StatusGone, map[string]any{"error": "legacy address generation is disabled"})
}

func (s *server) gasfreeAccount(w http.ResponseWriter, _ *http.Request, body []byte) {
	if !s.gasfreeEnabled || !s.gasfreeClient.Ready() || len(s.seed) == 0 {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{"error": "gasfree is disabled"})
		return
	}
	var request gasfreeAccountRequest
	if json.Unmarshal(body, &request) != nil || request.AppID == 0 || request.UserID == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid request"})
		return
	}
	derived, err := tron.Derive(s.seed, request.AppID, request.UserID)
	if err != nil {
		writeJSON(w, http.StatusUnprocessableEntity, map[string]any{"error": err.Error()})
		return
	}
	account, err := s.gasfreeClient.Account(derived.Address)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{"error": err.Error()})
		return
	}
	if account.AccountAddress != derived.Address {
		writeJSON(w, http.StatusBadGateway, map[string]any{"error": "gasfree EOA mismatch"})
		return
	}
	providers, err := s.gasfreeClient.Providers()
	if err != nil || len(providers) == 0 {
		writeJSON(w, http.StatusBadGateway, map[string]any{"error": "gasfree provider unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"eoa_address": derived.Address, "gasfree_address": account.GasFreeAddress, "provider_address": providers[0].Address, "active": account.Active, "allow_submit": account.AllowSubmit, "recommended_nonce": account.Nonce, "assets": account.Assets})
}

func (s *server) auth(next func(http.ResponseWriter, *http.Request, []byte)) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		body, err := io.ReadAll(io.LimitReader(r.Body, 64<<10))
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid body"})
			return
		}
		timestamp := r.Header.Get("X-BIM-Timestamp")
		signature := strings.ToLower(strings.TrimSpace(r.Header.Get("X-BIM-Signature")))
		unix, err := strconv.ParseInt(timestamp, 10, 64)
		if err != nil || abs(time.Now().Unix()-unix) > 30 {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "expired request"})
			return
		}
		mac := hmac.New(sha256.New, []byte(s.secret))
		_, _ = fmt.Fprintf(mac, "%s\n%s", timestamp, body)
		expected := hex.EncodeToString(mac.Sum(nil))
		if !hmac.Equal([]byte(expected), []byte(signature)) {
			writeJSON(w, http.StatusUnauthorized, map[string]any{"error": "invalid signature"})
			return
		}
		next(w, r, body)
	}
}

func requestLimit(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.ContentLength > 64<<10 {
			writeJSON(w, http.StatusRequestEntityTooLarge, map[string]any{"error": "request too large"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func env(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func abs(value int64) int64 {
	if value < 0 {
		return -value
	}
	return value
}

var _ = errors.New
