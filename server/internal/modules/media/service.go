package media

import (
	"bim/server/internal/platform/config"
	"bim/server/internal/platform/database"
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type Asset struct {
	ID           uint64    `json:"id"`
	Kind         string    `json:"kind"`
	MIMEType     string    `json:"mime_type"`
	SizeBytes    int64     `json:"size_bytes"`
	OriginalName string    `json:"original_name"`
	URL          string    `json:"url"`
	ExpiresAt    time.Time `json:"expires_at"`
}
type Service struct {
	db         *database.DB
	root, base string
	secret     []byte
}

func NewService(db *database.DB, cfg config.StorageConfig, secret string) *Service {
	return &Service{db: db, root: cfg.Local.Root, base: strings.TrimRight(cfg.PublicBaseURL, "/"), secret: []byte(secret)}
}
func (s *Service) Upload(ctx context.Context, appID, userID uint64, kind string, file multipart.File, header *multipart.FileHeader) (Asset, error) {
	allowed, max, err := mediaPolicy(kind)
	if err != nil {
		return Asset{}, err
	}
	first := make([]byte, 512)
	n, readErr := io.ReadFull(file, first)
	if readErr != nil && readErr != io.ErrUnexpectedEOF {
		return Asset{}, readErr
	}
	mimeType := http.DetectContentType(first[:n])
	if !allowed[mimeType] {
		return Asset{}, fmt.Errorf("文件类型与内容不匹配")
	}
	keyBytes := make([]byte, 32)
	if _, err := rand.Read(keyBytes); err != nil {
		return Asset{}, err
	}
	key := time.Now().UTC().Format("2006/01/02/") + hex.EncodeToString(keyBytes) + extension(mimeType)
	target := filepath.Join(s.root, filepath.FromSlash(key))
	cleanRoot, _ := filepath.Abs(s.root)
	cleanTarget, _ := filepath.Abs(target)
	if !strings.HasPrefix(cleanTarget, cleanRoot+string(os.PathSeparator)) {
		return Asset{}, fmt.Errorf("invalid storage path")
	}
	if err := os.MkdirAll(filepath.Dir(cleanTarget), 0750); err != nil {
		return Asset{}, err
	}
	temp, err := os.CreateTemp(filepath.Dir(cleanTarget), ".upload-*")
	if err != nil {
		return Asset{}, err
	}
	defer func() { temp.Close(); os.Remove(temp.Name()) }()
	hash := sha256.New()
	writer := io.MultiWriter(temp, hash)
	if _, err := writer.Write(first[:n]); err != nil {
		return Asset{}, err
	}
	written, err := io.Copy(writer, io.LimitReader(file, max-int64(n)+1))
	if err != nil {
		return Asset{}, err
	}
	size := int64(n) + written
	if size > max {
		return Asset{}, fmt.Errorf("文件超过大小限制")
	}
	if err := temp.Sync(); err != nil {
		return Asset{}, err
	}
	if err := temp.Close(); err != nil {
		return Asset{}, err
	}
	if err := os.Chmod(temp.Name(), 0640); err != nil {
		return Asset{}, err
	}
	if err := os.Rename(temp.Name(), cleanTarget); err != nil {
		return Asset{}, err
	}
	now := time.Now().UTC()
	result, err := s.db.ExecContext(ctx, `INSERT INTO media_assets(app_id,owner_id,object_key,original_name,media_kind,mime_type,size_bytes,sha256,status,created_at) VALUES(?,?,?,?,?,?,?,?,'ready',?)`, appID, userID, key, safeName(header.Filename), kind, mimeType, size, hex.EncodeToString(hash.Sum(nil)), now)
	if err != nil {
		os.Remove(cleanTarget)
		return Asset{}, err
	}
	id, _ := result.LastInsertId()
	if _, err := s.db.ExecContext(ctx, `INSERT INTO media_access(asset_id,app_id,user_id,granted_at) VALUES(?,?,?,?)`, id, appID, userID, now); err != nil {
		return Asset{}, err
	}
	return s.Resolve(ctx, appID, userID, uint64(id))
}
func (s *Service) Resolve(ctx context.Context, appID, userID, id uint64) (Asset, error) {
	var asset Asset
	var key string
	err := s.db.QueryRowContext(ctx, `SELECT ma.id,ma.media_kind,ma.mime_type,ma.size_bytes,ma.original_name,ma.object_key FROM media_assets ma JOIN media_access ac ON ac.asset_id=ma.id AND ac.app_id=ma.app_id WHERE ma.app_id=? AND ma.id=? AND ac.user_id=? AND ma.status='ready'`, appID, id, userID).Scan(&asset.ID, &asset.Kind, &asset.MIMEType, &asset.SizeBytes, &asset.OriginalName, &key)
	if err != nil {
		return Asset{}, sql.ErrNoRows
	}
	asset.ExpiresAt = time.Now().UTC().Add(15 * time.Minute)
	asset.URL = s.signedURL(asset.ID, asset.ExpiresAt)
	return asset, nil
}
func (s *Service) Open(id uint64, expires int64, signature string) (string, string, error) {
	if expires < time.Now().Unix() || expires > time.Now().Add(20*time.Minute).Unix() {
		return "", "", errors.New("expired")
	}
	expected := s.sign(id, expires)
	if !hmac.Equal([]byte(expected), []byte(signature)) {
		return "", "", errors.New("bad signature")
	}
	var key, mime string
	if err := s.db.QueryRow(`SELECT object_key,mime_type FROM media_assets WHERE id=? AND status='ready'`, id).Scan(&key, &mime); err != nil {
		return "", "", err
	}
	path := filepath.Join(s.root, filepath.FromSlash(key))
	root, _ := filepath.Abs(s.root)
	absolute, _ := filepath.Abs(path)
	if !strings.HasPrefix(absolute, root+string(os.PathSeparator)) {
		return "", "", errors.New("bad path")
	}
	return absolute, mime, nil
}
func (s *Service) signedURL(id uint64, expires time.Time) string {
	exp := expires.Unix()
	return s.base + "/api/v2/media/" + strconv.FormatUint(id, 10) + "/content?expires=" + strconv.FormatInt(exp, 10) + "&signature=" + s.sign(id, exp)
}
func (s *Service) sign(id uint64, expires int64) string {
	mac := hmac.New(sha256.New, s.secret)
	fmt.Fprintf(mac, "%d:%d", id, expires)
	return hex.EncodeToString(mac.Sum(nil))
}
func mediaPolicy(kind string) (map[string]bool, int64, error) {
	switch kind {
	case "image":
		return map[string]bool{"image/jpeg": true, "image/png": true, "image/webp": true, "image/gif": true}, 20 << 20, nil
	case "video":
		return map[string]bool{"video/mp4": true, "video/webm": true, "video/quicktime": true}, 200 << 20, nil
	case "voice":
		return map[string]bool{"audio/mpeg": true, "audio/ogg": true, "audio/mp4": true, "audio/webm": true, "audio/wav": true}, 30 << 20, nil
	case "file":
		return map[string]bool{"application/pdf": true, "application/zip": true, "application/octet-stream": true, "text/plain; charset=utf-8": true}, 200 << 20, nil
	case "sticker":
		return map[string]bool{"image/png": true, "image/webp": true, "image/gif": true}, 10 << 20, nil
	}
	return nil, 0, fmt.Errorf("媒体类型无效")
}
func extension(mime string) string {
	switch mime {
	case "image/jpeg":
		return ".jpg"
	case "image/png":
		return ".png"
	case "image/webp":
		return ".webp"
	case "image/gif":
		return ".gif"
	case "video/mp4":
		return ".mp4"
	case "video/webm":
		return ".webm"
	case "video/quicktime":
		return ".mov"
	case "audio/mpeg":
		return ".mp3"
	case "audio/ogg":
		return ".ogg"
	case "audio/mp4":
		return ".m4a"
	case "audio/webm":
		return ".webm"
	case "audio/wav":
		return ".wav"
	case "application/pdf":
		return ".pdf"
	case "application/zip":
		return ".zip"
	case "text/plain; charset=utf-8":
		return ".txt"
	}
	return ".bin"
}
func safeName(value string) string {
	value = filepath.Base(strings.TrimSpace(value))
	if len([]rune(value)) > 255 {
		return string([]rune(value)[:255])
	}
	return value
}
