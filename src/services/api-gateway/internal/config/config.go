package config

import (
	"os"
	"strconv"
	"strings"
)

// Config centralizes runtime settings for the API gateway.
type Config struct {
	Port                 string
	ServiceName          string
	ServiceVersion       string
	DefaultTimezone      string
	AuthEnabled          bool
	KeycloakIssuer       string
	KeycloakJWKSURL      string
	AllowedAudiences     []string
	TemplateReadRoles    []string
	TemplateEventRoles   []string
	AllowedOrigins       []string
	ObservabilityEnabled bool
	OTLPEndpoint         string
	OTLPInsecure         bool
	OTELSampleRatio      float64
	OTELEnvironment      string
	EDAEnabled           bool
	EDAExchange          string
	EDAExchangeType      string
	EDAQueue             string
	EDABindingKey        string
	EDARoutingKeyBase    string
	EDAConsumerEnabled   bool
	EDAConsumerTag       string
	EDAConsumerPrefetch  int
	RabbitMQURL          string
	RabbitMQHost         string
	RabbitMQPort         string
	RabbitMQUser         string
	RabbitMQPassword     string
	RabbitMQVHost        string
}

// Load reads runtime configuration from environment variables.
func Load() Config {
	return Config{
		Port:              envOrDefault("PORT", "8080"),
		ServiceName:       envOrDefault("SERVICE_NAME", "api-gateway"),
		ServiceVersion:    envOrDefault("SERVICE_VERSION", "0.1.0"),
		DefaultTimezone:   envOrDefault("DEFAULT_TIMEZONE", "__DEFAULT_TIMEZONE__"),
		AuthEnabled:       envBoolOrDefault("AUTH_ENABLED", true),
		KeycloakIssuer:    envOrDefault("AUTH_KEYCLOAK_ISSUER", "https://__HOST_SSO__/realms/__KEYCLOAK_REALM__"),
		KeycloakJWKSURL:   envOrDefault("AUTH_KEYCLOAK_JWKS_URL", "https://__HOST_SSO__/realms/__KEYCLOAK_REALM__/protocol/openid-connect/certs"),
		AllowedAudiences:  envCSVOrDefault("AUTH_ALLOWED_AUDIENCES", "__WEBAPP_CLIENT_ID__,__ADMIN_CLIENT_ID__"),
		TemplateReadRoles: envCSVOrDefault("AUTH_TEMPLATE_READ_ROLES", "platform_admin,platform_support"),
		TemplateEventRoles: envCSVOrDefault(
			"AUTH_TEMPLATE_EVENT_ROLES",
			"platform_admin,platform_support",
		),
		AllowedOrigins: envCSVOrDefault(
			"CORS_ALLOWED_ORIGINS",
			"https://__HOST_APP__,https://__HOST_ADMIN__,http://localhost:4173,http://127.0.0.1:4173",
		),
		ObservabilityEnabled: envBoolOrDefault("OTEL_ENABLED", true),
		OTLPEndpoint:         envOrDefault("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector.__K8S_NAMESPACE__.svc.cluster.local:4317"),
		OTLPInsecure:         envBoolOrDefault("OTEL_EXPORTER_OTLP_INSECURE", true),
		OTELSampleRatio:      envFloatOrDefault("OTEL_TRACES_SAMPLER_RATIO", 1.0),
		OTELEnvironment:      envOrDefault("OTEL_ENVIRONMENT", "platform"),
		EDAEnabled:           envBoolOrDefault("EDA_ENABLED", true),
		EDAExchange:          envOrDefault("EDA_EXCHANGE", "platform.events"),
		EDAExchangeType:      envOrDefault("EDA_EXCHANGE_TYPE", "topic"),
		EDAQueue:             envOrDefault("EDA_QUEUE", "api-gateway.events"),
		EDABindingKey:        envOrDefault("EDA_BINDING_KEY", "platform.api-gateway.#"),
		EDARoutingKeyBase:    envOrDefault("EDA_ROUTING_KEY_BASE", "platform.api-gateway"),
		EDAConsumerEnabled:   envBoolOrDefault("EDA_CONSUMER_ENABLED", true),
		EDAConsumerTag:       envOrDefault("EDA_CONSUMER_TAG", "api-gateway-consumer"),
		EDAConsumerPrefetch:  envIntOrDefault("EDA_CONSUMER_PREFETCH", 20),
		RabbitMQURL:          envOrDefault("RABBITMQ_URL", ""),
		RabbitMQHost:         envOrDefault("RABBITMQ_HOST", "rabbitmq.__K8S_NAMESPACE__.svc.cluster.local"),
		RabbitMQPort:         envOrDefault("RABBITMQ_PORT", "5672"),
		RabbitMQUser:         envOrDefault("RABBITMQ_USER", "guest"),
		RabbitMQPassword:     envOrDefault("RABBITMQ_PASSWORD", "guest"),
		RabbitMQVHost:        envOrDefault("RABBITMQ_VHOST", "/"),
	}
}

func envOrDefault(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func envBoolOrDefault(key string, fallback bool) bool {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}

	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func envCSVOrDefault(key, fallback string) []string {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		raw = fallback
	}

	items := strings.Split(raw, ",")
	out := make([]string, 0, len(items))
	for _, item := range items {
		value := strings.TrimSpace(item)
		if value == "" {
			continue
		}
		out = append(out, value)
	}
	return out
}

func envFloatOrDefault(key string, fallback float64) float64 {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}

	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil {
		return fallback
	}
	return parsed
}

func envIntOrDefault(key string, fallback int) int {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}

	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}
