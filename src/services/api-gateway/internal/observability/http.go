package observability

import (
	"log"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/otel/trace"
)

var (
	metricsOnce sync.Once

	httpRequestsTotal    *prometheus.CounterVec
	httpRequestDurationS *prometheus.HistogramVec
)

func ensureMetrics() {
	metricsOnce.Do(func() {
		httpRequestsTotal = prometheus.NewCounterVec(
			prometheus.CounterOpts{
				Name: "platform_http_server_requests_total",
				Help: "Total de requests HTTP atendidos pelo servico.",
			},
			[]string{"service", "method", "path", "status"},
		)
		httpRequestDurationS = prometheus.NewHistogramVec(
			prometheus.HistogramOpts{
				Name:    "platform_http_server_request_duration_seconds",
				Help:    "Duracao dos requests HTTP em segundos.",
				Buckets: []float64{0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10},
			},
			[]string{"service", "method", "path", "status"},
		)

		prometheus.MustRegister(httpRequestsTotal, httpRequestDurationS)
	})
}

// MetricsHandler returns a handler for Prometheus scraping.
func MetricsHandler() http.Handler {
	ensureMetrics()
	return promhttp.Handler()
}

// HTTPMetricsMiddleware captures request counters and latency histograms.
func HTTPMetricsMiddleware(next http.Handler, serviceName string) http.Handler {
	ensureMetrics()

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := &statusRecorder{ResponseWriter: w, statusCode: http.StatusOK}
		start := time.Now()

		next.ServeHTTP(rec, r)

		status := strconv.Itoa(rec.statusCode)
		labels := prometheus.Labels{
			"service": serviceName,
			"method":  r.Method,
			"path":    r.URL.Path,
			"status":  status,
		}
		httpRequestsTotal.With(labels).Inc()
		httpRequestDurationS.With(labels).Observe(time.Since(start).Seconds())
	})
}

// HTTPRequestLogMiddleware logs request metadata and trace correlation ids.
func HTTPRequestLogMiddleware(next http.Handler, logger *log.Logger, serviceName string) http.Handler {
	if logger == nil {
		return next
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := &statusRecorder{ResponseWriter: w, statusCode: http.StatusOK}
		start := time.Now()

		next.ServeHTTP(rec, r)

		durationMs := time.Since(start).Milliseconds()
		traceID := "-"
		spanID := "-"
		spanContext := trace.SpanContextFromContext(r.Context())
		if spanContext.IsValid() {
			traceID = spanContext.TraceID().String()
			spanID = spanContext.SpanID().String()
		}

		logger.Printf(
			"http_request service=%s method=%s path=%s status=%d duration_ms=%d trace_id=%s span_id=%s",
			serviceName,
			r.Method,
			r.URL.Path,
			rec.statusCode,
			durationMs,
			traceID,
			spanID,
		)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	statusCode int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.statusCode = code
	r.ResponseWriter.WriteHeader(code)
}
