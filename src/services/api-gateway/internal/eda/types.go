package eda

import (
	"context"
	"encoding/json"
	"time"
)

// Event is the canonical message envelope shared across producer/consumer flows.
type Event struct {
	ID        string            `json:"id"`
	Type      string            `json:"type"`
	Source    string            `json:"source"`
	Timestamp time.Time         `json:"timestamp"`
	TraceID   string            `json:"trace_id,omitempty"`
	Principal string            `json:"principal,omitempty"`
	Payload   json.RawMessage   `json:"payload"`
	Metadata  map[string]string `json:"metadata,omitempty"`
}

// Delivery wraps consumed events with broker metadata.
type Delivery struct {
	RoutingKey string            `json:"routing_key"`
	Event      Event             `json:"event"`
	Headers    map[string]string `json:"headers,omitempty"`
}

// Handler processes consumed events.
type Handler func(context.Context, Delivery) error

// Producer publishes events to the broker.
type Producer interface {
	Publish(ctx context.Context, routingKey string, event Event) error
}

// Consumer subscribes to events from the broker.
type Consumer interface {
	Start(ctx context.Context, handler Handler) error
}
