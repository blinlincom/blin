package userprofile

import (
	"context"
	"fmt"
	"strings"
)

type Service struct{ repository Repository }

func NewService(repository Repository) *Service { return &Service{repository: repository} }
func (s *Service) Profile(ctx context.Context, appID, userID uint64) (Profile, error) {
	return s.repository.Profile(ctx, appID, userID)
}
func (s *Service) UpdateProfile(ctx context.Context, appID, userID uint64, input Profile) (Profile, error) {
	input.Nickname = strings.TrimSpace(input.Nickname)
	input.Bio = strings.TrimSpace(input.Bio)
	input.Region = strings.TrimSpace(input.Region)
	if input.Nickname == "" || len([]rune(input.Nickname)) > 100 || len([]rune(input.Bio)) > 300 || len([]rune(input.Region)) > 100 {
		return Profile{}, fmt.Errorf("invalid profile")
	}
	if input.Gender > 2 {
		return Profile{}, fmt.Errorf("invalid gender")
	}
	return s.repository.UpdateProfile(ctx, appID, userID, input)
}
func (s *Service) Settings(ctx context.Context, appID, userID uint64) (Settings, error) {
	return s.repository.Settings(ctx, appID, userID)
}
func (s *Service) UpdateSettings(ctx context.Context, appID, userID uint64, input Settings) (Settings, error) {
	return s.repository.UpdateSettings(ctx, appID, userID, input)
}
func (s *Service) Devices(ctx context.Context, appID, userID uint64, currentSession string) ([]DeviceSession, error) {
	return s.repository.Devices(ctx, appID, userID, currentSession)
}
func (s *Service) RevokeDevice(ctx context.Context, appID, userID uint64, sessionID, currentSession string) error {
	if strings.TrimSpace(sessionID) == "" || sessionID == currentSession {
		return ErrForbidden
	}
	return s.repository.RevokeDevice(ctx, appID, userID, sessionID, currentSession)
}
