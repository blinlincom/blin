package social

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"
)

func TestApplyFriendRejectsSelf(t *testing.T) {
	service := NewService(stubRepository{})
	if _, err := service.ApplyFriend(context.Background(), 1, 7, 7, "hello"); !errors.Is(err, ErrForbidden) {
		t.Fatalf("error=%v", err)
	}
}

func TestCreateGroupDeduplicatesMembersAndIncludesOwner(t *testing.T) {
	repository := &captureRepository{}
	service := NewService(repository)
	group, err := service.CreateGroup(context.Background(), 1, 9, "Team", []uint64{3, 9, 3, 5})
	if err != nil {
		t.Fatal(err)
	}
	if group.ChannelID == "" || len(repository.memberIDs) != 3 {
		t.Fatalf("group=%+v members=%v", group, repository.memberIDs)
	}
	if repository.memberIDs[0] != 3 || repository.memberIDs[1] != 5 || repository.memberIDs[2] != 9 {
		t.Fatalf("members=%v", repository.memberIDs)
	}
}

type stubRepository struct{}

func (stubRepository) SearchUserByUsername(context.Context, uint64, string) (UserSummary, error) {
	return UserSummary{}, nil
}
func (stubRepository) ListFriends(context.Context, uint64, uint64, string) ([]UserSummary, error) {
	return nil, nil
}
func (stubRepository) CreateFriendRequest(context.Context, uint64, uint64, uint64, string) (uint64, error) {
	return 1, nil
}
func (stubRepository) ListFriendRequests(context.Context, uint64, uint64) ([]FriendRequest, error) {
	return nil, nil
}
func (stubRepository) HandleFriendRequest(context.Context, uint64, uint64, uint64, bool) error {
	return nil
}
func (stubRepository) DeleteFriendship(context.Context, uint64, uint64, uint64) error { return nil }
func (stubRepository) CreateGroup(context.Context, uint64, uint64, string, []uint64) (Group, error) {
	return Group{}, nil
}
func (stubRepository) ListGroups(context.Context, uint64, uint64) ([]Group, error) { return nil, nil }
func (stubRepository) GetGroup(context.Context, uint64, uint64, uint64) (Group, error) {
	return Group{}, nil
}
func (stubRepository) ListGroupMembers(context.Context, uint64, uint64, uint64) ([]GroupMember, error) {
	return nil, nil
}
func (stubRepository) AddGroupMembers(context.Context, uint64, uint64, uint64, []uint64) error {
	return nil
}
func (stubRepository) RemoveGroupMember(context.Context, uint64, uint64, uint64, uint64) error {
	return nil
}
func (stubRepository) UpdateGroup(context.Context, uint64, uint64, uint64, GroupUpdate) error {
	return nil
}
func (stubRepository) SetGroupMemberRole(context.Context, uint64, uint64, uint64, uint64, string) error {
	return nil
}
func (stubRepository) MuteGroupMember(context.Context, uint64, uint64, uint64, uint64, *time.Time) error {
	return nil
}
func (stubRepository) LeaveGroup(context.Context, uint64, uint64, uint64) error    { return nil }
func (stubRepository) DissolveGroup(context.Context, uint64, uint64, uint64) error { return nil }

type captureRepository struct {
	stubRepository
	memberIDs []uint64
}

func (r *captureRepository) CreateGroup(_ context.Context, appID uint64, _ uint64, _ string, memberIDs []uint64) (Group, error) {
	r.memberIDs = append([]uint64(nil), memberIDs...)
	return Group{ChannelID: fmt.Sprintf("app%dgroup1", appID)}, nil
}
