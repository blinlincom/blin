package moments

import "time"

type Media struct {
	Type             string `json:"type"`
	AssetID          uint64 `json:"asset_id"`
	ThumbnailAssetID uint64 `json:"thumbnail_asset_id,omitempty"`
	Width            int    `json:"width,omitempty"`
	Height           int    `json:"height,omitempty"`
	DurationMS       int64  `json:"duration_ms,omitempty"`
}
type Author struct {
	ID            uint64 `json:"id"`
	Nickname      string `json:"nickname"`
	AvatarAssetID uint64 `json:"avatar_asset_id"`
}
type Comment struct {
	ID            uint64    `json:"id"`
	Author        Author    `json:"author"`
	ReplyToUserID *uint64   `json:"reply_to_user_id,omitempty"`
	Content       string    `json:"content"`
	CreatedAt     time.Time `json:"created_at"`
}
type Moment struct {
	ID           uint64    `json:"id"`
	Author       Author    `json:"author"`
	Content      string    `json:"content"`
	Media        []Media   `json:"media"`
	Visibility   string    `json:"visibility"`
	Status       string    `json:"status"`
	ReviewReason string    `json:"review_reason,omitempty"`
	Liked        bool      `json:"liked"`
	Likes        []Author  `json:"likes"`
	Comments     []Comment `json:"comments"`
	CreatedAt    time.Time `json:"created_at"`
}
