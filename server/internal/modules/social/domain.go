package social

import (
	"context"
	"errors"
	"time"
)

var (
	ErrNotFound       = errors.New("not found")
	ErrAlreadyFriends = errors.New("already friends")
	ErrRequestPending = errors.New("friend request pending")
	ErrForbidden      = errors.New("forbidden")
)

type UserSummary struct {
	ID            uint64 `json:"id"`
	Username      string `json:"username"`
	Nickname      string `json:"nickname"`
	AvatarAssetID uint64 `json:"avatar_asset_id,omitempty"`
	Remark        string `json:"remark,omitempty"`
}

type FriendRequest struct {
	ID          uint64      `json:"id"`
	Requester   UserSummary `json:"requester"`
	Message     string      `json:"message"`
	Status      string      `json:"status"`
	CreatedAt   time.Time   `json:"created_at"`
	RecipientID uint64      `json:"-"`
}

type Group struct {
	ID                 uint64    `json:"id"`
	ChannelID          string    `json:"channel_id"`
	Name               string    `json:"name"`
	AvatarAssetID      uint64    `json:"avatar_asset_id,omitempty"`
	Announcement       string    `json:"announcement"`
	AllMuted           bool      `json:"all_muted"`
	InviteConfirmation bool      `json:"invite_confirmation"`
	OwnerID            uint64    `json:"owner_id"`
	MemberCount        uint32    `json:"member_count"`
	JoinHistoryPolicy  string    `json:"join_history_policy"`
	CreatedAt          time.Time `json:"created_at"`
}

type GroupMember struct {
	User          UserSummary `json:"user"`
	Role          string      `json:"role"`
	GroupNickname string      `json:"group_nickname"`
	MutedUntil    *time.Time  `json:"muted_until,omitempty"`
	JoinedAt      time.Time   `json:"joined_at"`
}

type GroupUpdate struct {
	Name               *string `json:"name,omitempty"`
	AvatarAssetID      *uint64 `json:"avatar_asset_id,omitempty"`
	Announcement       *string `json:"announcement,omitempty"`
	AllMuted           *bool   `json:"all_muted,omitempty"`
	InviteConfirmation *bool   `json:"invite_confirmation,omitempty"`
}

type Repository interface {
	SearchUserByUsername(ctx context.Context, appID uint64, username string) (UserSummary, error)
	ListFriends(ctx context.Context, appID, userID uint64, query string) ([]UserSummary, error)
	CreateFriendRequest(ctx context.Context, appID, requesterID, recipientID uint64, message string) (uint64, error)
	ListFriendRequests(ctx context.Context, appID, recipientID uint64) ([]FriendRequest, error)
	HandleFriendRequest(ctx context.Context, appID, requestID, recipientID uint64, accept bool) error
	DeleteFriendship(ctx context.Context, appID, userID, friendID uint64) error
	CreateGroup(ctx context.Context, appID, ownerID uint64, name string, memberIDs []uint64) (Group, error)
	ListGroups(ctx context.Context, appID, userID uint64) ([]Group, error)
	GetGroup(ctx context.Context, appID, groupID, userID uint64) (Group, error)
	ListGroupMembers(ctx context.Context, appID, groupID, userID uint64) ([]GroupMember, error)
	AddGroupMembers(ctx context.Context, appID, groupID, actorID uint64, memberIDs []uint64) error
	RemoveGroupMember(ctx context.Context, appID, groupID, actorID, memberID uint64) error
	UpdateGroup(ctx context.Context, appID, groupID, actorID uint64, update GroupUpdate) error
	SetGroupMemberRole(ctx context.Context, appID, groupID, actorID, memberID uint64, role string) error
	MuteGroupMember(ctx context.Context, appID, groupID, actorID, memberID uint64, until *time.Time) error
	LeaveGroup(ctx context.Context, appID, groupID, userID uint64) error
	DissolveGroup(ctx context.Context, appID, groupID, ownerID uint64) error
}
