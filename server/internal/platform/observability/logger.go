package observability

import (
	"log/slog"
	"os"
)

func NewLogger(environment string) *slog.Logger {
	level := slog.LevelInfo
	if environment == "development" || environment == "test" {
		level = slog.LevelDebug
	}
	return slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level}))
}
