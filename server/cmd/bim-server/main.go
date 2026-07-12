package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"bim/server/internal/bootstrap"
	"bim/server/internal/modules/adminauth"
	"bim/server/internal/platform/authn"
	"bim/server/internal/platform/config"
	"bim/server/internal/platform/database"
	"bim/server/internal/platform/observability"
	"bim/server/migrations"
)

var version = "dev"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	switch os.Args[1] {
	case "serve":
		serve(os.Args[2:])
	case "doctor":
		doctor(os.Args[2:])
	case "migrate":
		migrate(os.Args[2:])
	case "admin-create":
		adminCreate(os.Args[2:])
	case "version":
		fmt.Println(version)
	default:
		usage()
		os.Exit(2)
	}
}

func adminCreate(args []string) {
	flags := flag.NewFlagSet("admin-create", flag.ExitOnError)
	configPath := flags.String("config", "configs/config.yaml", "YAML config path")
	username := flags.String("username", "", "administrator username")
	passwordFile := flags.String("password-file", "", "file containing administrator password")
	_ = flags.Parse(args)
	cfg, err := config.Load(*configPath)
	if err != nil {
		fatal(err)
	}
	password := ""
	if *passwordFile != "" {
		content, readErr := os.ReadFile(*passwordFile)
		if readErr != nil {
			fatal(readErr)
		}
		password = strings.TrimSpace(string(content))
	} else {
		password = strings.TrimSpace(os.Getenv("BIM_ADMIN_PASSWORD"))
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	db, err := database.Open(ctx, cfg.Database)
	if err != nil {
		fatal(err)
	}
	defer db.Close()
	tokens, err := authn.NewTokenManager(cfg.Security.TokenSigningKey)
	if err != nil {
		fatal(err)
	}
	service := adminauth.NewService(adminauth.NewSQLRepository(db), tokens)
	if err := service.CreateSuperAdmin(ctx, *username, password); err != nil {
		fatal(err)
	}
	fmt.Println("admin=created")
}

func migrate(args []string) {
	flags := flag.NewFlagSet("migrate", flag.ExitOnError)
	configPath := flags.String("config", "configs/config.yaml", "YAML config path")
	statusOnly := flags.Bool("status", false, "show migration status without applying")
	_ = flags.Parse(args)
	cfg, err := config.Load(*configPath)
	if err != nil {
		fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	db, err := database.Open(ctx, cfg.Database)
	if err != nil {
		fatal(err)
	}
	defer db.Close()
	runner := migrations.New(db.DB)
	if *statusOnly {
		statuses, err := runner.Status(ctx)
		if err != nil {
			fatal(err)
		}
		for _, status := range statuses {
			fmt.Printf("%06d applied=%t %s\n", status.Version, status.Applied, status.Name)
		}
		return
	}
	if err := runner.Up(ctx); err != nil {
		fatal(err)
	}
	fmt.Println("migrations=ok")
}

func serve(args []string) {
	flags := flag.NewFlagSet("serve", flag.ExitOnError)
	configPath := flags.String("config", "configs/config.yaml", "YAML config path")
	_ = flags.Parse(args)
	cfg, err := config.Load(*configPath)
	if err != nil {
		fatal(err)
	}
	logger := observability.NewLogger(cfg.Server.Env)
	startupCtx, startupCancel := context.WithTimeout(context.Background(), 10*time.Second)
	dependencies, err := bootstrap.BuildDependencies(startupCtx, cfg, logger)
	startupCancel()
	if err != nil {
		fatal(err)
	}
	app := bootstrap.New(cfg, logger, version, dependencies)
	server := &http.Server{
		Addr: cfg.Server.Listen, Handler: app.Handler,
		ReadHeaderTimeout: 10 * time.Second, ReadTimeout: 30 * time.Second,
		WriteTimeout: 30 * time.Second, IdleTimeout: 120 * time.Second,
		MaxHeaderBytes: 16 << 10,
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go func() {
		logger.Info("bim server listening", "listen", cfg.Server.Listen, "roles", cfg.Server.Roles, "version", version)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logger.Error("http server failed", "error", err)
			stop()
		}
	}()
	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.Server.ShutdownTimeout.Value())
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		logger.Error("shutdown failed", "error", err)
	}
	if err := app.Close(shutdownCtx); err != nil {
		logger.Error("close dependencies failed", "error", err)
	}
}

func doctor(args []string) {
	flags := flag.NewFlagSet("doctor", flag.ExitOnError)
	configPath := flags.String("config", "configs/config.yaml", "YAML config path")
	_ = flags.Parse(args)
	cfg, err := config.Load(*configPath)
	if err != nil {
		fatal(err)
	}
	fmt.Printf("config=ok env=%s roles=%v digital_assets=%t otc=%t\n", cfg.Server.Env, cfg.Server.Roles, cfg.Features.DigitalAssets, cfg.Features.OTC)
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: bim-server <serve|doctor|migrate|admin-create|version> [options]")
}
