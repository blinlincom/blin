package identity

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"bim/server/internal/platform/authn"
)

func TestRegisterAndLoginRotatePlatformSession(t *testing.T) {
	tokens, _ := authn.NewTokenManager(strings.Repeat("k", 32))
	repository := newMemoryRepository()
	service := NewService(repository, tokens)
	registered, err := service.Register(context.Background(), RegisterInput{AppID: 1, Username: "Alice_01", Nickname: "Alice", Password: "safe-password-123", Device: Device{Platform: "android", ID: "phone-a"}})
	if err != nil {
		t.Fatal(err)
	}
	if registered.User.Username != "alice_01" || registered.RefreshToken == "" {
		t.Fatalf("registered=%+v", registered)
	}
	loggedIn, err := service.Login(context.Background(), LoginInput{AppID: 1, Username: "ALICE_01", Password: "safe-password-123", Device: Device{Platform: "android", ID: "phone-b"}})
	if err != nil {
		t.Fatal(err)
	}
	if repository.activePlatformSessions("android") != 1 {
		t.Fatal("old platform session was not revoked")
	}
	if loggedIn.SessionID == registered.SessionID {
		t.Fatal("session ID was not rotated")
	}
}

func TestLoginDoesNotRevealMissingUser(t *testing.T) {
	tokens, _ := authn.NewTokenManager(strings.Repeat("k", 32))
	service := NewService(newMemoryRepository(), tokens)
	_, err := service.Login(context.Background(), LoginInput{AppID: 1, Username: "missing", Password: "wrong-password", Device: Device{Platform: "ios", ID: "phone"}})
	if !errors.Is(err, ErrInvalidCredentials) {
		t.Fatalf("error=%v", err)
	}
}

func TestRefreshKeepsUserProfileAndRotatesToken(t *testing.T) {
	tokens, _ := authn.NewTokenManager(strings.Repeat("k", 32))
	service := NewService(newMemoryRepository(), tokens)
	registered, err := service.Register(context.Background(), RegisterInput{AppID: 1, Username: "Alice_01", Nickname: "Alice", Password: "safe-password-123", Device: Device{Platform: "android", ID: "phone-a"}})
	if err != nil {
		t.Fatal(err)
	}
	refreshed, err := service.Refresh(context.Background(), registered.RefreshToken)
	if err != nil {
		t.Fatal(err)
	}
	if refreshed.User.Username != "alice_01" || refreshed.User.Nickname != "Alice" {
		t.Fatalf("profile lost during refresh: %+v", refreshed.User)
	}
	if refreshed.RefreshToken == registered.RefreshToken {
		t.Fatal("refresh token was not rotated")
	}
	if _, err := service.Refresh(context.Background(), registered.RefreshToken); !errors.Is(err, ErrSessionRevoked) {
		t.Fatalf("replayed refresh token error=%v", err)
	}
}

func TestAuthenticateRejectsReplacedPlatformSession(t *testing.T) {
	tokens, _ := authn.NewTokenManager(strings.Repeat("k", 32))
	repository := newMemoryRepository()
	service := NewService(repository, tokens)
	first, err := service.Register(context.Background(), RegisterInput{AppID: 1, Username: "Alice_01", Nickname: "Alice", Password: "safe-password-123", Device: Device{Platform: "android", ID: "phone-a"}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := service.Login(context.Background(), LoginInput{AppID: 1, Username: "alice_01", Password: "safe-password-123", Device: Device{Platform: "android", ID: "phone-b"}}); err != nil {
		t.Fatal(err)
	}
	if _, err := service.Authenticate(context.Background(), first.AccessToken); !errors.Is(err, ErrSessionRevoked) {
		t.Fatalf("replaced access token error=%v", err)
	}
}

type memoryRepository struct {
	users    map[string]User
	sessions map[string]Session
	nextID   uint64
}

func newMemoryRepository() *memoryRepository {
	return &memoryRepository{users: map[string]User{}, sessions: map[string]Session{}, nextID: 1}
}

func (m *memoryRepository) CreateUser(_ context.Context, user User, session Session) (User, error) {
	key := strings.ToLower(user.Username)
	if _, exists := m.users[key]; exists {
		return User{}, ErrUsernameTaken
	}
	user.ID, user.SessionVersion = m.nextID, 1
	m.nextID++
	m.users[key] = user
	session.UserID, session.AppID = user.ID, user.AppID
	m.sessions[session.ID] = session
	return user, nil
}
func (m *memoryRepository) FindPasswordUser(_ context.Context, _ uint64, username string) (User, error) {
	user, ok := m.users[strings.ToLower(username)]
	if !ok {
		return User{}, errors.New("not found")
	}
	return user, nil
}
func (m *memoryRepository) FindUserByID(_ context.Context, appID, userID uint64) (User, error) {
	for _, user := range m.users {
		if user.AppID == appID && user.ID == userID {
			return user, nil
		}
	}
	return User{}, errors.New("not found")
}
func (m *memoryRepository) ReplacePlatformSession(_ context.Context, user User, session Session) error {
	for id, item := range m.sessions {
		if item.UserID == user.ID && item.Platform == session.Platform {
			delete(m.sessions, id)
		}
	}
	m.sessions[session.ID] = session
	return nil
}
func (m *memoryRepository) FindSession(_ context.Context, id string) (Session, error) {
	item, ok := m.sessions[id]
	if !ok {
		return Session{}, ErrSessionRevoked
	}
	return item, nil
}
func (m *memoryRepository) RotateSession(_ context.Context, id, hash string, expires time.Time) error {
	item, ok := m.sessions[id]
	if !ok {
		return ErrSessionRevoked
	}
	item.RefreshTokenHash, item.ExpiresAt = hash, expires
	m.sessions[id] = item
	return nil
}
func (m *memoryRepository) RevokeSession(_ context.Context, id string) error {
	delete(m.sessions, id)
	return nil
}
func (m *memoryRepository) SecurityMethods(context.Context, uint64, uint64) ([]SecurityMethod, error) {
	return nil, nil
}
func (m *memoryRepository) BindSecurityMethod(context.Context, uint64, uint64, string, string) error {
	return nil
}
func (m *memoryRepository) activePlatformSessions(platform string) int {
	count := 0
	for _, session := range m.sessions {
		if session.Platform == platform {
			count++
		}
	}
	return count
}
