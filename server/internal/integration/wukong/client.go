package wukong

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"bim/server/internal/modules/messaging"
)

type Client struct {
	baseURL, token string
	http           *http.Client
}

type ChannelOperation struct {
	Operation string
	ChannelID string
	Members   []string
}

func New(baseURL, token string) *Client {
	return &Client{baseURL: strings.TrimRight(baseURL, "/"), token: token, http: &http.Client{Timeout: 5 * time.Second}}
}

func (c *Client) Send(ctx context.Context, request messaging.SenderRequest) (messaging.SenderResponse, error) {
	if strings.TrimSpace(request.ClientMsgNo) == "" {
		return messaging.SenderResponse{}, fmt.Errorf("client_msg_no is required")
	}
	if request.ChannelType != messaging.ChannelPerson && request.ChannelType != messaging.ChannelGroup {
		return messaging.SenderResponse{}, fmt.Errorf("invalid channel_type")
	}
	if err := messaging.ValidateContentType(request.ContentType); err != nil {
		return messaging.SenderResponse{}, err
	}
	header, err := messaging.HeaderFor(request.ContentType, request.System)
	if err != nil {
		return messaging.SenderResponse{}, err
	}
	payload, err := json.Marshal(request.Payload)
	if err != nil {
		return messaging.SenderResponse{}, err
	}
	body := map[string]any{"from_uid": request.FromUID, "channel_id": request.ChannelID, "channel_type": request.ChannelType, "client_msg_no": request.ClientMsgNo, "payload": base64.StdEncoding.EncodeToString(payload), "header": header}
	var raw struct {
		MessageID   string `json:"message_idstr"`
		MessageSeq  uint64 `json:"message_seq"`
		ClientMsgNo string `json:"client_msg_no"`
	}
	if err := c.request(ctx, http.MethodPost, "/message/send", body, &raw); err != nil {
		return messaging.SenderResponse{}, err
	}
	return messaging.SenderResponse{MessageID: raw.MessageID, MessageSeq: raw.MessageSeq, ClientMsgNo: raw.ClientMsgNo}, nil
}

func (c *Client) ApplyChannelOperation(ctx context.Context, operation ChannelOperation) error {
	if strings.TrimSpace(operation.ChannelID) == "" {
		return fmt.Errorf("channel_id is required")
	}
	body := map[string]any{
		"channel_id":   operation.ChannelID,
		"channel_type": messaging.ChannelGroup,
		"subscribers":  operation.Members,
	}
	switch operation.Operation {
	case "subscriber_add":
		body["reset"] = 0
		body["temp_subscriber"] = 0
		return c.request(ctx, http.MethodPost, "/channel/subscriber_add", body, nil)
	case "subscriber_remove":
		return c.request(ctx, http.MethodPost, "/channel/subscriber_remove", body, nil)
	case "channel_delete":
		return c.request(ctx, http.MethodDelete, "/channel/delete", map[string]any{"channel_id": operation.ChannelID, "channel_type": messaging.ChannelGroup}, nil)
	default:
		return fmt.Errorf("unsupported channel operation %q", operation.Operation)
	}
}

func (c *Client) request(ctx context.Context, method, path string, input, output any) error {
	encoded, err := json.Marshal(input)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, method, c.baseURL+path, bytes.NewReader(encoded))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("token", c.token)
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 2<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("wukong status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	if output != nil && len(body) > 0 {
		if err := json.Unmarshal(body, output); err != nil {
			return fmt.Errorf("decode wukong response: %w", err)
		}
	}
	return nil
}
