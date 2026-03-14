package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/example/template-api-gateway/internal/app"
	"github.com/example/template-api-gateway/internal/config"
	"github.com/example/template-api-gateway/internal/eda"
	"github.com/example/template-api-gateway/internal/observability"
)

func main() {
	cfg := config.Load()
	logger := log.New(os.Stdout, "", log.LstdFlags|log.LUTC)
	observabilityShutdown := func(context.Context) error { return nil }
	eventBusShutdown := func(context.Context) error { return nil }
	eventProducer := eda.Producer(eda.NewNoopProducer())
	eventConsumer := eda.Consumer(eda.NewNoopConsumer())

	if cfg.EDAEnabled {
		eventBus, busErr := eda.NewRabbitMQ(eda.RabbitMQConfig{
			URL:          cfg.RabbitMQURL,
			Host:         cfg.RabbitMQHost,
			Port:         cfg.RabbitMQPort,
			User:         cfg.RabbitMQUser,
			Password:     cfg.RabbitMQPassword,
			VHost:        cfg.RabbitMQVHost,
			Exchange:     cfg.EDAExchange,
			ExchangeType: cfg.EDAExchangeType,
			Queue:        cfg.EDAQueue,
			BindingKey:   cfg.EDABindingKey,
			ConsumerTag:  cfg.EDAConsumerTag,
			Prefetch:     cfg.EDAConsumerPrefetch,
			Logger:       logger,
		})
		if busErr != nil {
			logger.Printf("eda setup failed; continuing with no-op producer/consumer: %v", busErr)
		} else {
			eventProducer = eventBus
			eventConsumer = eventBus
			eventBusShutdown = eventBus.Shutdown
			logger.Printf(
				"eda configured (exchange=%s queue=%s binding_key=%s consumer_enabled=%t)",
				cfg.EDAExchange,
				cfg.EDAQueue,
				cfg.EDABindingKey,
				cfg.EDAConsumerEnabled,
			)
		}
	} else {
		logger.Print("eda disabled")
	}

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
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = eventBusShutdown(shutdownCtx)
	}()

	authorizer, err := app.NewAuthorizer(app.AuthorizerConfig{
		Enabled:            cfg.AuthEnabled,
		Issuer:             cfg.KeycloakIssuer,
		JWKSURL:            cfg.KeycloakJWKSURL,
		AllowedAudiences:   cfg.AllowedAudiences,
		TemplateReadRoles:  cfg.TemplateReadRoles,
		TemplateEventRoles: cfg.TemplateEventRoles,
		Logger:             logger,
	})
	if err != nil {
		logger.Fatalf("failed to initialize auth middleware: %v", err)
	}

	server := &http.Server{
		Addr: ":" + cfg.Port,
		Handler: app.NewRouter(app.RouterOptions{
			Authorizer:          authorizer,
			ServiceName:         cfg.ServiceName,
			Version:             cfg.ServiceVersion,
			DefaultTimezone:     cfg.DefaultTimezone,
			AuthEnabled:         cfg.AuthEnabled,
			AllowedOrigins:      cfg.AllowedOrigins,
			TracingEnabled:      cfg.ObservabilityEnabled,
			TracingServiceName:  cfg.ServiceName,
			EDAEnabled:          cfg.EDAEnabled,
			EventProducer:       eventProducer,
			EventRoutingKeyBase: cfg.EDARoutingKeyBase,
			Logger:              logger,
		}),
		ReadHeaderTimeout: app.ReadHeaderTimeout,
	}

	shutdownSignalCtx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	if cfg.EDAEnabled && cfg.EDAConsumerEnabled {
		go func() {
			if consumerErr := eventConsumer.Start(shutdownSignalCtx, func(_ context.Context, delivery eda.Delivery) error {
				logger.Printf(
					"eda_event_consumed event_id=%s type=%s routing_key=%s trace_id=%s source=%s",
					delivery.Event.ID,
					delivery.Event.Type,
					delivery.RoutingKey,
					delivery.Event.TraceID,
					delivery.Event.Source,
				)
				return nil
			}); consumerErr != nil && !errors.Is(consumerErr, context.Canceled) {
				logger.Printf("eda consumer stopped with error: %v", consumerErr)
			}
		}()
	}

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
