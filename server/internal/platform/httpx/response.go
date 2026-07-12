package httpx

import (
	"encoding/json"
	"net/http"
)

type Envelope struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	Data      any    `json:"data,omitempty"`
	RequestID string `json:"request_id,omitempty"`
}

func JSON(w http.ResponseWriter, status int, body Envelope) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func OK(w http.ResponseWriter, r *http.Request, data any) {
	JSON(w, http.StatusOK, Envelope{
		Code: "OK", Message: "success", Data: data, RequestID: RequestID(r.Context()),
	})
}

func Error(w http.ResponseWriter, r *http.Request, status int, code, message string) {
	JSON(w, status, Envelope{Code: code, Message: message, RequestID: RequestID(r.Context())})
}
