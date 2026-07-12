package social

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"
)

type Service struct{ repository Repository }

func NewService(repository Repository) *Service { return &Service{repository: repository} }

func (s *Service) SearchForAdd(ctx context.Context, appID uint64, username string) (UserSummary, error) {
	username = strings.ToLower(strings.TrimSpace(username))
	if appID == 0 || username == "" {
		return UserSummary{}, ErrNotFound
	}
	return s.repository.SearchUserByUsername(ctx, appID, username)
}

func (s *Service) ListFriends(ctx context.Context, appID, userID uint64, query string) ([]UserSummary, error) {
	return s.repository.ListFriends(ctx, appID, userID, strings.TrimSpace(query))
}

func (s *Service) ListFriendRequests(ctx context.Context, appID, recipientID uint64) ([]FriendRequest, error) {
	return s.repository.ListFriendRequests(ctx, appID, recipientID)
}

func (s *Service) ApplyFriend(ctx context.Context, appID, requesterID, recipientID uint64, message string) (uint64, error) {
	if appID == 0 || requesterID == 0 || recipientID == 0 || requesterID == recipientID {
		return 0, ErrForbidden
	}
	message = strings.TrimSpace(message)
	if len([]rune(message)) > 200 {
		return 0, fmt.Errorf("friend request message is too long")
	}
	return s.repository.CreateFriendRequest(ctx, appID, requesterID, recipientID, message)
}

func (s *Service) HandleFriendRequest(ctx context.Context, appID, requestID, recipientID uint64, accept bool) error {
	return s.repository.HandleFriendRequest(ctx, appID, requestID, recipientID, accept)
}

func (s *Service) DeleteFriendship(ctx context.Context, appID, userID, friendID uint64) error {
	if appID == 0 || userID == 0 || friendID == 0 || userID == friendID {
		return ErrForbidden
	}
	return s.repository.DeleteFriendship(ctx, appID, userID, friendID)
}

func (s *Service) CreateGroup(ctx context.Context, appID, ownerID uint64, name string, memberIDs []uint64) (Group, error) {
	name = strings.TrimSpace(name)
	if appID == 0 || ownerID == 0 || name == "" || len([]rune(name)) > 100 {
		return Group{}, fmt.Errorf("invalid group")
	}
	unique := map[uint64]struct{}{ownerID: {}}
	for _, id := range memberIDs {
		if id != 0 {
			unique[id] = struct{}{}
		}
	}
	ids := make([]uint64, 0, len(unique))
	for id := range unique {
		ids = append(ids, id)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	return s.repository.CreateGroup(ctx, appID, ownerID, name, ids)
}

func (s *Service) ListGroups(ctx context.Context, appID, userID uint64) ([]Group, error) {
	return s.repository.ListGroups(ctx, appID, userID)
}

func (s *Service) GetGroup(ctx context.Context, appID, groupID, userID uint64) (Group, error) {
	return s.repository.GetGroup(ctx, appID, groupID, userID)
}

func (s *Service) ListGroupMembers(ctx context.Context, appID, groupID, userID uint64) ([]GroupMember, error) {
	return s.repository.ListGroupMembers(ctx, appID, groupID, userID)
}

func normalizeIDs(values []uint64) []uint64 {
	unique := make(map[uint64]struct{}, len(values))
	for _, value := range values {
		if value != 0 {
			unique[value] = struct{}{}
		}
	}
	result := make([]uint64, 0, len(unique))
	for value := range unique {
		result = append(result, value)
	}
	sort.Slice(result, func(i, j int) bool { return result[i] < result[j] })
	return result
}

func (s *Service) AddGroupMembers(ctx context.Context, appID, groupID, actorID uint64, memberIDs []uint64) error {
	ids := normalizeIDs(memberIDs)
	if len(ids) == 0 || len(ids) > 200 {
		return ErrForbidden
	}
	return s.repository.AddGroupMembers(ctx, appID, groupID, actorID, ids)
}

func (s *Service) RemoveGroupMember(ctx context.Context, appID, groupID, actorID, memberID uint64) error {
	if memberID == 0 || actorID == memberID {
		return ErrForbidden
	}
	return s.repository.RemoveGroupMember(ctx, appID, groupID, actorID, memberID)
}

func (s *Service) UpdateGroup(ctx context.Context, appID, groupID, actorID uint64, update GroupUpdate) error {
	if update.Name != nil {
		value := strings.TrimSpace(*update.Name)
		if value == "" || len([]rune(value)) > 100 {
			return fmt.Errorf("invalid group name")
		}
		update.Name = &value
	}
	if update.Announcement != nil {
		value := strings.TrimSpace(*update.Announcement)
		if len([]rune(value)) > 2000 {
			return fmt.Errorf("announcement is too long")
		}
		update.Announcement = &value
	}
	return s.repository.UpdateGroup(ctx, appID, groupID, actorID, update)
}

func (s *Service) SetGroupMemberRole(ctx context.Context, appID, groupID, actorID, memberID uint64, role string) error {
	role = strings.TrimSpace(role)
	if role != "admin" && role != "member" {
		return ErrForbidden
	}
	return s.repository.SetGroupMemberRole(ctx, appID, groupID, actorID, memberID, role)
}

func (s *Service) MuteGroupMember(ctx context.Context, appID, groupID, actorID, memberID uint64, until *time.Time) error {
	if until != nil {
		value := until.UTC()
		if value.Before(time.Now().UTC()) {
			return ErrForbidden
		}
		until = &value
	}
	return s.repository.MuteGroupMember(ctx, appID, groupID, actorID, memberID, until)
}

func (s *Service) LeaveGroup(ctx context.Context, appID, groupID, userID uint64) error {
	return s.repository.LeaveGroup(ctx, appID, groupID, userID)
}

func (s *Service) DissolveGroup(ctx context.Context, appID, groupID, ownerID uint64) error {
	return s.repository.DissolveGroup(ctx, appID, groupID, ownerID)
}
