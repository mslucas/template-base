package app

import (
	"encoding/json"
	"log"
	"net/http"
	"runtime"
	"strings"
	"time"

	"github.com/example/template-api-gateway/internal/observability"
	"github.com/example/template-api-gateway/internal/openapi"
	"github.com/gorilla/websocket"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

const (
	// ReadHeaderTimeout protects against slowloris-like attacks on headers.
	ReadHeaderTimeout = 10 * time.Second
)

var wsUpgrader = websocket.Upgrader{
	CheckOrigin: func(_ *http.Request) bool {
		return true
	},
}

type statusResponse struct {
	Service         string    `json:"service"`
	Version         string    `json:"version"`
	Timestamp       time.Time `json:"timestamp"`
	Runtime         string    `json:"runtime"`
	DefaultTimezone string    `json:"default_timezone"`
	AuthEnabled     bool      `json:"auth_enabled"`
}

type wsEnvelope struct {
	Type      string    `json:"type"`
	Payload   string    `json:"payload"`
	Timestamp time.Time `json:"timestamp"`
}

type secureResponse struct {
	Status    string   `json:"status"`
	Principal string   `json:"principal"`
	Roles     []string `json:"roles"`
}

// RouterOptions controls middleware behavior for HTTP routes.
type RouterOptions struct {
	Authorizer         *Authorizer
	ServiceName        string
	Version            string
	DefaultTimezone    string
	AuthEnabled        bool
	AllowedOrigins     []string
	TracingEnabled     bool
	TracingServiceName string
	Logger             *log.Logger
}

// NewRouter defines the base HTTP contract for the API gateway.
func NewRouter(options RouterOptions) http.Handler {
	allowedOriginSet := toSet(options.AllowedOrigins)
	serviceName := fallback(options.ServiceName, "api-gateway")
	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
	})

	mux.HandleFunc("/api/v1/platform/meta", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, statusResponse{
			Service:         fallback(options.ServiceName, "api-gateway"),
			Version:         fallback(options.Version, "0.1.0"),
			Timestamp:       time.Now().UTC(),
			Runtime:         runtime.Version(),
			DefaultTimezone: fallback(options.DefaultTimezone, "UTC"),
			AuthEnabled:     options.AuthEnabled,
		})
	})

	mux.HandleFunc("/api/v1/template/secure", func(w http.ResponseWriter, r *http.Request) {
		claims, ok := ClaimsFromContext(r.Context())
		if !ok || claims == nil {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "missing auth context"})
			return
		}
		principal := claims.PreferredUsername
		if strings.TrimSpace(principal) == "" {
			principal = claims.Email
		}
		writeJSON(w, http.StatusOK, secureResponse{
			Status:    "ok",
			Principal: fallback(principal, "unknown"),
			Roles:     claims.RealmAccess.Roles,
		})
	})

	mux.HandleFunc("/swagger/openapi.yaml", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/yaml")
		_, _ = w.Write(openapi.Spec)
	})

	mux.Handle("/metrics", observability.MetricsHandler())

	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		origin := strings.TrimSpace(r.Header.Get("Origin"))
		if !isAllowedOrigin(origin, allowedOriginSet) {
			http.Error(w, "origin not allowed", http.StatusForbidden)
			return
		}

		conn, err := wsUpgrader.Upgrade(w, r, nil)
		if err != nil {
			http.Error(w, "websocket upgrade failed", http.StatusBadRequest)
			return
		}
		defer conn.Close()

		for {
			msgType, message, err := conn.ReadMessage()
			if err != nil {
				return
			}

			envelope := wsEnvelope{
				Type:      "echo",
				Payload:   string(message),
				Timestamp: time.Now().UTC(),
			}
			bytes, _ := json.Marshal(envelope)
			if err = conn.WriteMessage(msgType, bytes); err != nil {
				return
			}
		}
	})

	var handler http.Handler = mux
	if options.Authorizer != nil {
		handler = options.Authorizer.Middleware(handler)
	}
	handler = withCORS(handler, allowedOriginSet)
	handler = observability.HTTPMetricsMiddleware(handler, serviceName)
	handler = observability.HTTPRequestLogMiddleware(handler, options.Logger, serviceName)

	if options.TracingEnabled {
		handler = otelhttp.NewHandler(
			handler,
			fallback(options.TracingServiceName, serviceName),
			otelhttp.WithSpanNameFormatter(func(_ string, r *http.Request) string {
				return r.Method + " " + r.URL.Path
			}),
		)
	}

	return handler
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func withCORS(next http.Handler, allowed map[string]struct{}) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := strings.TrimSpace(r.Header.Get("Origin"))
		if origin != "" && isAllowedOrigin(origin, allowed) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PATCH,OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type,Authorization,X-Timezone")
			w.Header().Set("Access-Control-Allow-Credentials", "true")
		}

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func isAllowedOrigin(origin string, allowed map[string]struct{}) bool {
	if strings.TrimSpace(origin) == "" {
		return true
	}
	if _, ok := allowed[origin]; ok {
		return true
	}
	return strings.Contains(origin, "localhost") || strings.Contains(origin, "127.0.0.1")
}

func fallback(value, defaultValue string) string {
	if strings.TrimSpace(value) == "" {
		return defaultValue
	}
	return value
}
