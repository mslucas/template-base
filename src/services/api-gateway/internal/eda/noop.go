package eda

import "context"

// NoopProducer provides a safe fallback when broker integration is unavailable.
type NoopProducer struct{}

// NewNoopProducer returns a producer that drops events.
func NewNoopProducer() *NoopProducer {
	return &NoopProducer{}
}

// Publish is intentionally a no-op.
func (*NoopProducer) Publish(context.Context, string, Event) error {
	return nil
}

// NoopConsumer provides a safe fallback when broker integration is unavailable.
type NoopConsumer struct{}

// NewNoopConsumer returns a consumer that waits for context cancellation.
func NewNoopConsumer() *NoopConsumer {
	return &NoopConsumer{}
}

// Start blocks until context cancellation.
func (*NoopConsumer) Start(ctx context.Context, _ Handler) error {
	<-ctx.Done()
	return nil
}
