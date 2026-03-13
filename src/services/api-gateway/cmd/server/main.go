package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/example/template-api-gateway/internal/app"
	"github.com/example/template-api-gateway/internal/config"
	"github.com/example/template-api-gateway/internal/observability"
)

func main() {
	cfg := config.Load()
	logger := log.New(os.Stdout, "", log.LstdFlags|log.LUTC)
	observabilityShutdown := func(context.Context) error { return nil }

	obsShutdown, err := observability.Setup(context.Background(), observability.Config{
		Enabled:        cfg.ObservabilityEnabled,
		ServiceName:    cfg.ServiceName,
		ServiceVersion: cfg.ServiceVersion,
		Environment:    cfg.OTELEnvironment,
		OTLPEndpoint:   cfg.OTLPEndpoint,
		OTLPInsecure:   cfg.OTLPInsecure,
		SampleRatio:    cfg.OTELSampleRatio,
	})
	if err != nil {
		logger.Printf("observability setup failed; continuing without tracing: %v", err)
	} else {
		observabilityShutdown = obsShutdown
		logger.Printf(
			"observability configured (enabled=%t endpoint=%s sample_ratio=%.2f)",
			cfg.ObservabilityEnabled,
			cfg.OTLPEndpoint,
			cfg.OTELSampleRatio,
		)
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = observabilityShutdown(shutdownCtx)
	}()

	authorizer, err := app.NewAuthorizer(app.AuthorizerConfig{
		Enabled:           cfg.AuthEnabled,
		Issuer:            cfg.KeycloakIssuer,
		JWKSURL:           cfg.KeycloakJWKSURL,
		AllowedAudiences:  cfg.AllowedAudiences,
		TemplateReadRoles: cfg.TemplateReadRoles,
		Logger:            logger,
	})
	if err != nil {
		logger.Fatalf("failed to initialize auth middleware: %v", err)
	}

	server := &http.Server{
		Addr: ":" + cfg.Port,
		Handler: app.NewRouter(app.RouterOptions{
			Authorizer:         authorizer,
			ServiceName:        cfg.ServiceName,
			Version:            cfg.ServiceVersion,
			DefaultTimezone:    cfg.DefaultTimezone,
			AuthEnabled:        cfg.AuthEnabled,
			AllowedOrigins:     cfg.AllowedOrigins,
			TracingEnabled:     cfg.ObservabilityEnabled,
			TracingServiceName: cfg.ServiceName,
			Logger:             logger,
		}),
		ReadHeaderTimeout: app.ReadHeaderTimeout,
	}

	shutdownSignalCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	go func() {
		<-shutdownSignalCtx.Done()
		logger.Print("shutdown signal received")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdownCtx)
	}()

	logger.Printf("%s listening on :%s", cfg.ServiceName, cfg.Port)
	if err = server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		logger.Fatalf("server failed: %v", err)
	}
}
