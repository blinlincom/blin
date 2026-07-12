package bootstrap

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"slices"
	"sync"

	"bim/server/internal/integration/wukong"
	"bim/server/internal/modules/adminauth"
	"bim/server/internal/modules/adminconfig"
	"bim/server/internal/modules/adminmoments"
	"bim/server/internal/modules/adminops"
	"bim/server/internal/modules/adminportal"
	"bim/server/internal/modules/adminwallet"
	"bim/server/internal/modules/appconfig"
	"bim/server/internal/modules/calls"
	"bim/server/internal/modules/engagement"
	"bim/server/internal/modules/gateway"
	"bim/server/internal/modules/identity"
	"bim/server/internal/modules/media"
	"bim/server/internal/modules/messaging"
	"bim/server/internal/modules/messagingwebhook"
	"bim/server/internal/modules/moments"
	"bim/server/internal/modules/portal"
	"bim/server/internal/modules/serviceaccount"
	"bim/server/internal/modules/social"
	"bim/server/internal/modules/userprofile"
	"bim/server/internal/modules/verification"
	"bim/server/internal/modules/wallet"
	"bim/server/internal/platform/authn"
	"bim/server/internal/platform/config"
	"bim/server/internal/platform/database"
	"bim/server/internal/platform/health"
	"bim/server/internal/platform/redisx"
	webhookauth "bim/server/internal/platform/webhook"
)

// BuildDependencies opens mandatory infrastructure before the HTTP listener is
// exposed. A process that cannot authenticate users or reach its state stores
// must fail startup instead of accepting partially functional traffic.
func BuildDependencies(ctx context.Context, cfg config.Config, logger *slog.Logger) (Dependencies, error) {
	db, err := database.Open(ctx, cfg.Database)
	if err != nil {
		return Dependencies{}, err
	}
	redisClient, err := redisx.Open(ctx, cfg.Redis)
	if err != nil {
		_ = db.Close()
		return Dependencies{}, err
	}
	tokens, err := authn.NewTokenManager(cfg.Security.TokenSigningKey)
	if err != nil {
		_ = redisClient.Close()
		_ = db.Close()
		return Dependencies{}, fmt.Errorf("initialize token manager: %w", err)
	}
	appPolicy := appconfig.New("", db)
	verificationService := verification.NewService(db, cfg.Security.RequestSigningKey, cfg.Verification)
	identityService := identity.NewService(identity.NewSQLRepository(db), tokens, appPolicy, verificationService)
	profileService := userprofile.NewService(userprofile.NewSQLRepository(db))
	adminAuthService := adminauth.NewService(adminauth.NewSQLRepository(db), tokens)
	socialService := social.NewService(social.NewSQLRepository(db))
	walletService := wallet.NewService(wallet.NewSQLRepository(db), cfg.Wallet.PaymentPasswordMaxAttempts, cfg.Wallet.PaymentPasswordLock.Value(), verificationService)
	callService := calls.NewService(db, cfg.LiveKit)
	gatewayService := gateway.NewService(redisClient, cfg.Gateway)
	publisher := gateway.NewPublisher(redisClient, db, cfg.Gateway.StreamMaxLen)
	messageService := messaging.NewService(messaging.NewSQLRepository(db), publisher)
	webhookVerifier := webhookauth.NewVerifier(cfg.WuKongIM.WebhookSecret, cfg.Security.ReplayWindow.Value(), redisClient)
	workerCtx, stopWorkers := context.WithCancel(context.Background())
	var workers sync.WaitGroup
	if slices.Contains(cfg.Server.Roles, "worker") {
		hostname, _ := os.Hostname()
		wukongClient := wukong.New(cfg.WuKongIM.BaseURL, cfg.WuKongIM.ManagerToken)
		dispatcher := messaging.NewDispatcher(db, wukongClient, hostname)
		channelDispatcher := wukong.NewChannelDispatcher(db, wukongClient, hostname)
		workers.Add(1)
		go func() {
			defer workers.Done()
			_ = dispatcher.Run(workerCtx)
		}()
		workers.Add(1)
		go func() {
			defer workers.Done()
			_ = channelDispatcher.Run(workerCtx)
		}()
	}
	if slices.Contains(cfg.Server.Roles, "scheduler") {
		scheduler := wallet.NewScheduler(walletService, logger)
		workers.Add(1)
		go func() { defer workers.Done(); _ = scheduler.Run(workerCtx) }()
	}
	return Dependencies{
		Database:              db,
		IdentityHandler:       identity.NewHandler(identityService),
		UserProfileHandler:    userprofile.NewHandler(profileService),
		VerificationHandler:   verification.NewHandler(verificationService),
		AdminAuthHandler:      adminauth.NewHandler(adminAuthService),
		AdminWalletHandler:    adminwallet.NewHandler(db),
		AdminConfigHandler:    adminconfig.NewHandler(appPolicy, db),
		AdminMomentsHandler:   adminmoments.NewHandler(db),
		AdminOpsHandler:       adminops.NewHandler(db),
		AdminPortalHandler:    adminportal.NewHandler(db),
		SocialHandler:         social.NewHandler(socialService),
		ServiceAccountHandler: serviceaccount.NewHandler(serviceaccount.NewService(db)),
		MessageHandler:        messaging.NewHandler(messageService),
		MediaHandler:          media.NewHandler(media.NewService(db, cfg.Storage, cfg.Security.FieldEncryptionKey)),
		MomentsHandler:        moments.NewHandler(moments.NewService(db)),
		CallsHandler:          calls.NewHandler(callService),
		CallsWebhookHandler:   calls.NewWebhookHandler(callService),
		EngagementHandler:     engagement.NewHandler(db),
		PortalHandler:         portal.NewHandler(db),
		WebhookHandler:        messagingwebhook.NewHandler(db, webhookVerifier, publisher, cfg.WuKongIM.WebhookSecret),
		GatewayService:        gatewayService,
		WalletHandler:         wallet.NewHandler(walletService, db, cfg.Security.FieldEncryptionKey),
		HealthChecks: map[string]health.Check{
			"mysql": db.PingContext,
			"redis": func(checkCtx context.Context) error {
				return redisClient.Ping(checkCtx).Err()
			},
		},
		Close: func(context.Context) error {
			stopWorkers()
			workers.Wait()
			return errors.Join(redisClient.Close(), db.Close())
		},
	}, nil
}
