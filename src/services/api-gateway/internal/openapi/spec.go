package openapi

import _ "embed"

// Spec is the embedded OpenAPI contract for the gateway.
//
//go:embed openapi.yaml
var Spec []byte
