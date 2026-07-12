package wallet

import (
	"context"
	"log/slog"
	"time"
)

type Scheduler struct {
	service *Service
	logger  *slog.Logger
}

func NewScheduler(service *Service, logger *slog.Logger) *Scheduler {
	return &Scheduler{service: service, logger: logger}
}
func (s *Scheduler) Run(ctx context.Context) error {
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			if _, err := s.service.RefundExpiredTransfers(ctx, 200); err != nil && s.logger != nil {
				s.logger.Error("refund expired transfers failed", "error", err)
			}
			if _, err := s.service.RefundExpiredRedPackets(ctx, 200); err != nil && s.logger != nil {
				s.logger.Error("refund expired red packets failed", "error", err)
			}
		}
	}
}
