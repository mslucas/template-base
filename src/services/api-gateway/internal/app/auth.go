package app

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	authHeaderBearerPrefix = "Bearer "
)

type contextKey string

const authClaimsContextKey contextKey = "auth.claims"

// AuthorizerConfig configures JWT validation and role enforcement.
type AuthorizerConfig struct {
	Enabled            bool
	Issuer             string
	JWKSURL            string
	AllowedAudiences   []string
	TemplateReadRoles  []string
	TemplateEventRoles []string
	Logger             *log.Logger
}

// Authorizer applies JWT + RBAC rules for protected endpoints.
type Authorizer struct {
	enabled bool
	logger  *log.Logger

	validator *JWTValidator

	templateReadRoles  map[string]struct{}
	templateEventRoles map[string]struct{}
}

// AccessClaims models Keycloak access token fields used by API auth.
type AccessClaims struct {
	RealmAccess struct {
		Roles []string `json:"roles"`
	} `json:"realm_access"`
	Azp               string `json:"azp"`
	PreferredUsername string `json:"preferred_username"`
	Email             string `json:"email"`

	jwt.RegisteredClaims
}

// JWTValidator verifies signatures against Keycloak JWKS.
type JWTValidator struct {
	issuer  string
	jwksURL string

	allowedAudiences map[string]struct{}
	httpClient       *http.Client

	mu   sync.RWMutex
	keys map[string]*rsa.PublicKey
}

// NewAuthorizer constructs endpoint protection middleware.
func NewAuthorizer(cfg AuthorizerConfig) (*Authorizer, error) {
	logger := cfg.Logger
	if logger == nil {
		logger = log.Default()
	}

	a := &Authorizer{
		enabled:            cfg.Enabled,
		logger:             logger,
		templateReadRoles:  toSet(cfg.TemplateReadRoles),
		templateEventRoles: toSet(cfg.TemplateEventRoles),
	}
	if len(a.templateEventRoles) == 0 {
		a.templateEventRoles = a.templateReadRoles
	}

	if !cfg.Enabled {
		return a, nil
	}

	if strings.TrimSpace(cfg.Issuer) == "" {
		return nil, errors.New("auth enabled but issuer is empty")
	}
	if strings.TrimSpace(cfg.JWKSURL) == "" {
		return nil, errors.New("auth enabled but jwks url is empty")
	}

	a.validator = &JWTValidator{
		issuer:           strings.TrimSpace(cfg.Issuer),
		jwksURL:          strings.TrimSpace(cfg.JWKSURL),
		allowedAudiences: toSet(cfg.AllowedAudiences),
		httpClient: &http.Client{
			Timeout: 6 * time.Second,
		},
		keys: make(map[string]*rsa.PublicKey),
	}

	if err := a.validator.refreshKeys(context.Background()); err != nil {
		return nil, fmt.Errorf("load jwks: %w", err)
	}

	return a, nil
}

// Middleware protects selected routes by method/path and required roles.
func (a *Authorizer) Middleware(next http.Handler) http.Handler {
	if a == nil || !a.enabled {
		return next
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodOptions {
			next.ServeHTTP(w, r)
			return
		}

		requiredRoles, protected := a.requiredRoles(r.Method, r.URL.Path)
		if !protected {
			next.ServeHTTP(w, r)
			return
		}

		token, err := bearerTokenFromRequest(r)
		if err != nil {
			writeJSONAuthError(w, http.StatusUnauthorized, "missing or invalid bearer token")
			return
		}

		claims, err := a.validator.Validate(r.Context(), token)
		if err != nil {
			a.logger.Printf("auth validation failed: %v", err)
			writeJSONAuthError(w, http.StatusUnauthorized, "invalid token")
			return
		}

		if len(requiredRoles) > 0 && !claims.HasAnyRole(requiredRoles) {
			writeJSONAuthError(w, http.StatusForbidden, "insufficient role")
			return
		}

		ctx := context.WithValue(r.Context(), authClaimsContextKey, claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// ClaimsFromContext retrieves validated token claims if present.
func ClaimsFromContext(ctx context.Context) (*AccessClaims, bool) {
	claims, ok := ctx.Value(authClaimsContextKey).(*AccessClaims)
	if !ok || claims == nil {
		return nil, false
	}
	return claims, true
}

func (a *Authorizer) requiredRoles(method, path string) (map[string]struct{}, bool) {
	if method == http.MethodGet && path == "/api/v1/template/secure" {
		return a.templateReadRoles, true
	}
	if method == http.MethodPost && path == "/api/v1/template/events" {
		return a.templateEventRoles, true
	}
	return nil, false
}

func bearerTokenFromRequest(r *http.Request) (string, error) {
	header := strings.TrimSpace(r.Header.Get("Authorization"))
	if !strings.HasPrefix(header, authHeaderBearerPrefix) {
		return "", errors.New("missing bearer prefix")
	}
	token := strings.TrimSpace(strings.TrimPrefix(header, authHeaderBearerPrefix))
	if token == "" {
		return "", errors.New("empty bearer token")
	}
	return token, nil
}

func (v *JWTValidator) Validate(ctx context.Context, rawToken string) (*AccessClaims, error) {
	claims := &AccessClaims{}

	parsed, err := jwt.ParseWithClaims(rawToken, claims, func(token *jwt.Token) (any, error) {
		if token.Method == nil || token.Method.Alg() == "" {
			return nil, errors.New("missing signing algorithm")
		}
		if !strings.HasPrefix(token.Method.Alg(), "RS") {
			return nil, fmt.Errorf("unsupported signing algorithm: %s", token.Method.Alg())
		}

		kid, _ := token.Header["kid"].(string)
		if strings.TrimSpace(kid) == "" {
			return nil, errors.New("missing kid header")
		}

		key := v.getKey(kid)
		if key != nil {
			return key, nil
		}

		if refreshErr := v.refreshKeys(ctx); refreshErr != nil {
			return nil, refreshErr
		}

		key = v.getKey(kid)
		if key == nil {
			return nil, fmt.Errorf("kid not found in jwks: %s", kid)
		}
		return key, nil
	}, jwt.WithIssuer(v.issuer), jwt.WithLeeway(10*time.Second))
	if err != nil {
		return nil, err
	}

	if !parsed.Valid {
		return nil, errors.New("token invalid")
	}

	if claims.ExpiresAt == nil || claims.ExpiresAt.Time.Before(time.Now().UTC()) {
		return nil, errors.New("token expired")
	}

	if !v.matchesAudience(claims) {
		return nil, errors.New("audience mismatch")
	}

	return claims, nil
}

func (v *JWTValidator) matchesAudience(claims *AccessClaims) bool {
	if len(v.allowedAudiences) == 0 {
		return true
	}

	for _, aud := range claims.Audience {
		if _, ok := v.allowedAudiences[aud]; ok {
			return true
		}
	}

	if _, ok := v.allowedAudiences[claims.Azp]; ok {
		return true
	}

	return false
}

func (v *JWTValidator) getKey(kid string) *rsa.PublicKey {
	v.mu.RLock()
	defer v.mu.RUnlock()
	return v.keys[kid]
}

func (v *JWTValidator) refreshKeys(ctx context.Context) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, v.jwksURL, nil)
	if err != nil {
		return err
	}

	resp, err := v.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("jwks endpoint returned status %d", resp.StatusCode)
	}

	var payload struct {
		Keys []struct {
			Kid string `json:"kid"`
			Kty string `json:"kty"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}

	if err = json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return err
	}

	nextKeys := make(map[string]*rsa.PublicKey)
	for _, key := range payload.Keys {
		if key.Kty != "RSA" || strings.TrimSpace(key.Kid) == "" {
			continue
		}
		pubKey, parseErr := rsaPublicKeyFromJWK(key.N, key.E)
		if parseErr != nil {
			continue
		}
		nextKeys[key.Kid] = pubKey
	}

	if len(nextKeys) == 0 {
		return errors.New("no rsa keys found in jwks")
	}

	v.mu.Lock()
	v.keys = nextKeys
	v.mu.Unlock()

	return nil
}

func rsaPublicKeyFromJWK(nEncoded, eEncoded string) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(nEncoded)
	if err != nil {
		return nil, err
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(eEncoded)
	if err != nil {
		return nil, err
	}

	n := new(big.Int).SetBytes(nBytes)
	e := new(big.Int).SetBytes(eBytes)
	if n.Sign() <= 0 || e.Sign() <= 0 {
		return nil, errors.New("invalid rsa jwk values")
	}

	return &rsa.PublicKey{
		N: n,
		E: int(e.Int64()),
	}, nil
}

func (c *AccessClaims) HasAnyRole(required map[string]struct{}) bool {
	if len(required) == 0 {
		return true
	}
	for _, role := range c.RealmAccess.Roles {
		if _, ok := required[role]; ok {
			return true
		}
	}
	return false
}

func writeJSONAuthError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": message})
}

func toSet(values []string) map[string]struct{} {
	result := make(map[string]struct{}, len(values))
	for _, value := range values {
		v := strings.TrimSpace(value)
		if v == "" {
			continue
		}
		result[v] = struct{}{}
	}
	return result
}
