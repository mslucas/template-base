package eda

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/url"
	"strings"
	"sync"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

const (
	defaultExchangeType = "topic"
	defaultBindingKey   = "#"
	defaultPrefetch     = 20
)

// RabbitMQConfig controls producer/consumer topology and connectivity.
type RabbitMQConfig struct {
	URL          string
	Host         string
	Port         string
	User         string
	Password     string
	VHost        string
	Exchange     string
	ExchangeType string
	Queue        string
	BindingKey   string
	ConsumerTag  string
	Prefetch     int
	Logger       *log.Logger
}

// RabbitMQBus implements both producer and consumer contracts.
type RabbitMQBus struct {
	cfg    RabbitMQConfig
	logger *log.Logger
	conn   *amqp.Connection

	producerMu sync.Mutex
	producerCh *amqp.Channel

	consumerMu sync.Mutex
	consumerCh *amqp.Channel
}

// NewRabbitMQ initializes topology and returns a ready-to-use bus.
func NewRabbitMQ(cfg RabbitMQConfig) (*RabbitMQBus, error) {
	cfg = cfg.withDefaults()
	if strings.TrimSpace(cfg.Exchange) == "" {
		return nil, errors.New("eda exchange is required")
	}
	if strings.TrimSpace(cfg.Queue) == "" {
		return nil, errors.New("eda queue is required")
	}

	conn, err := amqp.Dial(cfg.connectionURL())
	if err != nil {
		return nil, fmt.Errorf("rabbitmq dial: %w", err)
	}

	bus := &RabbitMQBus{
		cfg:  cfg,
		conn: conn,
	}
	if cfg.Logger != nil {
		bus.logger = cfg.Logger
	} else {
		bus.logger = log.Default()
	}

	if err = bus.openProducerChannel(); err != nil {
		_ = conn.Close()
		return nil, err
	}

	if err = bus.openConsumerChannel(); err != nil {
		_ = bus.closeProducerChannel()
		_ = conn.Close()
		return nil, err
	}

	return bus, nil
}

// Publish sends event payloads to the configured exchange.
func (b *RabbitMQBus) Publish(ctx context.Context, routingKey string, event Event) error {
	if b == nil {
		return errors.New("rabbitmq bus is nil")
	}

	routingKey = strings.TrimSpace(routingKey)
	if routingKey == "" {
		return errors.New("routing key is required")
	}
	if event.Timestamp.IsZero() {
		event.Timestamp = time.Now().UTC()
	}
	if strings.TrimSpace(event.ID) == "" {
		return errors.New("event id is required")
	}
	if strings.TrimSpace(event.Type) == "" {
		return errors.New("event type is required")
	}

	payload, err := json.Marshal(event)
	if err != nil {
		return fmt.Errorf("marshal event: %w", err)
	}

	headers := amqp.Table{}
	for k, v := range event.Metadata {
		key := strings.TrimSpace(k)
		if key == "" {
			continue
		}
		headers[key] = v
	}

	b.producerMu.Lock()
	defer b.producerMu.Unlock()

	if b.producerCh == nil {
		return errors.New("producer channel is closed")
	}

	err = b.producerCh.PublishWithContext(
		ctx,
		b.cfg.Exchange,
		routingKey,
		false,
		false,
		amqp.Publishing{
			DeliveryMode: amqp.Persistent,
			ContentType:  "application/json",
			Type:         event.Type,
			MessageId:    event.ID,
			Timestamp:    event.Timestamp.UTC(),
			Headers:      headers,
			Body:         payload,
		},
	)
	if err != nil {
		return fmt.Errorf("publish event: %w", err)
	}
	return nil
}

// Start consumes events from queue and dispatches them to the handler.
func (b *RabbitMQBus) Start(ctx context.Context, handler Handler) error {
	if b == nil {
		return errors.New("rabbitmq bus is nil")
	}
	if handler == nil {
		return errors.New("consumer handler is required")
	}

	b.consumerMu.Lock()
	ch := b.consumerCh
	b.consumerMu.Unlock()
	if ch == nil {
		return errors.New("consumer channel is closed")
	}

	deliveries, err := ch.Consume(
		b.cfg.Queue,
		b.cfg.ConsumerTag,
		false,
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		return fmt.Errorf("start consume: %w", err)
	}

	for {
		select {
		case <-ctx.Done():
			return nil
		case delivery, ok := <-deliveries:
			if !ok {
				return errors.New("delivery channel closed")
			}

			var event Event
			if err = json.Unmarshal(delivery.Body, &event); err != nil {
				b.logger.Printf("eda_consume_unmarshal_failed queue=%s err=%v", b.cfg.Queue, err)
				_ = delivery.Nack(false, false)
				continue
			}

			consumeErr := handler(ctx, Delivery{
				RoutingKey: delivery.RoutingKey,
				Event:      event,
				Headers:    tableToStringMap(delivery.Headers),
			})
			if consumeErr != nil {
				b.logger.Printf(
					"eda_consume_handler_failed queue=%s routing_key=%s event_id=%s err=%v",
					b.cfg.Queue,
					delivery.RoutingKey,
					event.ID,
					consumeErr,
				)
				_ = delivery.Nack(false, true)
				continue
			}

			if err = delivery.Ack(false); err != nil {
				return fmt.Errorf("ack delivery: %w", err)
			}
		}
	}
}

// Shutdown closes channels and connection with context-bound timeout semantics.
func (b *RabbitMQBus) Shutdown(ctx context.Context) error {
	if b == nil {
		return nil
	}

	done := make(chan error, 1)
	go func() {
		var errs []error
		if err := b.closeConsumerChannel(); err != nil {
			errs = append(errs, err)
		}
		if err := b.closeProducerChannel(); err != nil {
			errs = append(errs, err)
		}
		if b.conn != nil {
			if err := b.conn.Close(); err != nil && !errors.Is(err, amqp.ErrClosed) {
				errs = append(errs, err)
			}
		}
		done <- errors.Join(errs...)
	}()

	select {
	case <-ctx.Done():
		return ctx.Err()
	case err := <-done:
		return err
	}
}

func (b *RabbitMQBus) openProducerChannel() error {
	ch, err := b.conn.Channel()
	if err != nil {
		return fmt.Errorf("open producer channel: %w", err)
	}
	if err = declareTopology(ch, b.cfg); err != nil {
		_ = ch.Close()
		return err
	}

	b.producerMu.Lock()
	b.producerCh = ch
	b.producerMu.Unlock()
	return nil
}

func (b *RabbitMQBus) openConsumerChannel() error {
	ch, err := b.conn.Channel()
	if err != nil {
		return fmt.Errorf("open consumer channel: %w", err)
	}
	if err = declareTopology(ch, b.cfg); err != nil {
		_ = ch.Close()
		return err
	}

	if err = ch.Qos(b.cfg.Prefetch, 0, false); err != nil {
		_ = ch.Close()
		return fmt.Errorf("configure consumer qos: %w", err)
	}

	b.consumerMu.Lock()
	b.consumerCh = ch
	b.consumerMu.Unlock()
	return nil
}

func (b *RabbitMQBus) closeProducerChannel() error {
	b.producerMu.Lock()
	defer b.producerMu.Unlock()
	if b.producerCh == nil {
		return nil
	}
	err := b.producerCh.Close()
	if errors.Is(err, amqp.ErrClosed) {
		err = nil
	}
	b.producerCh = nil
	return err
}

func (b *RabbitMQBus) closeConsumerChannel() error {
	b.consumerMu.Lock()
	defer b.consumerMu.Unlock()
	if b.consumerCh == nil {
		return nil
	}
	err := b.consumerCh.Close()
	if errors.Is(err, amqp.ErrClosed) {
		err = nil
	}
	b.consumerCh = nil
	return err
}

func declareTopology(ch *amqp.Channel, cfg RabbitMQConfig) error {
	if err := ch.ExchangeDeclare(
		cfg.Exchange,
		cfg.ExchangeType,
		true,
		false,
		false,
		false,
		nil,
	); err != nil {
		return fmt.Errorf("declare exchange %s: %w", cfg.Exchange, err)
	}

	queue, err := ch.QueueDeclare(
		cfg.Queue,
		true,
		false,
		false,
		false,
		nil,
	)
	if err != nil {
		return fmt.Errorf("declare queue %s: %w", cfg.Queue, err)
	}

	if err = ch.QueueBind(
		queue.Name,
		cfg.BindingKey,
		cfg.Exchange,
		false,
		nil,
	); err != nil {
		return fmt.Errorf("bind queue %s to exchange %s: %w", queue.Name, cfg.Exchange, err)
	}

	return nil
}

func (cfg RabbitMQConfig) withDefaults() RabbitMQConfig {
	if strings.TrimSpace(cfg.Host) == "" {
		cfg.Host = "localhost"
	}
	if strings.TrimSpace(cfg.Port) == "" {
		cfg.Port = "5672"
	}
	if strings.TrimSpace(cfg.User) == "" {
		cfg.User = "guest"
	}
	if strings.TrimSpace(cfg.Password) == "" {
		cfg.Password = "guest"
	}
	if strings.TrimSpace(cfg.VHost) == "" {
		cfg.VHost = "/"
	}
	if strings.TrimSpace(cfg.ExchangeType) == "" {
		cfg.ExchangeType = defaultExchangeType
	}
	if strings.TrimSpace(cfg.BindingKey) == "" {
		cfg.BindingKey = defaultBindingKey
	}
	if cfg.Prefetch <= 0 {
		cfg.Prefetch = defaultPrefetch
	}
	return cfg
}

func (cfg RabbitMQConfig) connectionURL() string {
	if strings.TrimSpace(cfg.URL) != "" {
		return strings.TrimSpace(cfg.URL)
	}

	path := "/"
	if normalized := strings.TrimPrefix(strings.TrimSpace(cfg.VHost), "/"); normalized != "" {
		path = "/" + normalized
	}

	u := &url.URL{
		Scheme: "amqp",
		User:   url.UserPassword(cfg.User, cfg.Password),
		Host:   cfg.Host + ":" + cfg.Port,
		Path:   path,
	}
	return u.String()
}

func tableToStringMap(table amqp.Table) map[string]string {
	if len(table) == 0 {
		return nil
	}

	out := make(map[string]string, len(table))
	for k, v := range table {
		out[k] = fmt.Sprint(v)
	}
	return out
}
