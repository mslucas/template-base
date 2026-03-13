FROM golang:1.24.5 AS builder
WORKDIR /app
COPY . .
RUN go mod download && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /bin/api-gateway ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /bin/api-gateway /api-gateway
EXPOSE 8080
ENTRYPOINT ["/api-gateway"]
