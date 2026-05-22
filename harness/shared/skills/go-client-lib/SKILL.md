---
name: go-client-lib
description: "Activate when building or maintaining a Go gRPC client library — covers facade pattern, shared connections, proto generation with buf, event key management, and options pattern."
license: MIT
---

# Go gRPC Client Library Patterns

## Architecture

- **Facade pattern** with a single entry point per service
- Share a single gRPC connection across all RPC clients
- Use a **service registry** for connection management — never hardcode addresses
- Use generated protobuf code from a shared proto repository

## Service Registry

Use a centralized registry for inter-service connections instead of manual `grpc.NewClient`:

```go
// Service registry abstracts connection management
conn, err := registry.NewConn(registry.OrderService, &registry.Options{
    Log: logger,
    ENV: envVar,
})
if err != nil {
    return fmt.Errorf("connecting to order service: %w", err)
}

client := pb.NewOrderServiceClient(conn)
```

The registry handles:
- **Service discovery** — resolves addresses by service name
- **Credential management** — TLS/xDS in production, insecure in development
- **Connection pooling** — reuses connections across calls
- **Environment awareness** — different addresses per environment

### Why Not Manual Connections

```go
// DON'T — hardcoded, no service discovery, no credential management
conn, err := grpc.NewClient("localhost:50051",
    grpc.WithTransportCredentials(insecure.NewCredentials()))

// DO — service registry handles everything
conn, err := registry.NewConn(registry.OrderService, opts)
```

## Client Facade

```go
type Client struct {
    conn *grpc.ClientConn

    Orders    pb.OrderServiceClient
    Inventory pb.InventoryServiceClient
    Shipping  pb.ShippingServiceClient
}

func NewClient(conn *grpc.ClientConn) *Client {
    return &Client{
        conn:      conn,
        Orders:    pb.NewOrderServiceClient(conn),
        Inventory: pb.NewInventoryServiceClient(conn),
        Shipping:  pb.NewShippingServiceClient(conn),
    }
}
```

## Options Pattern

```go
type Options struct {
    Logger *slog.Logger
    ENV    string  // "local", "dev", "staging", "prod"
}
```

Support both development (insecure credentials) and production (TLS/xDS) via environment-aware options.

## Wrapper Methods

Add convenience methods on the facade for common operations:

```go
func (c *Client) GetOrder(ctx context.Context, id string) (*pb.OrderGetReply, error) {
    return c.Orders.Get(ctx, &pb.OrderGetRequest{OrderId: id})
}

func (c *Client) CreateOrder(ctx context.Context, items []*pb.OrderItem) (string, error) {
    reply, err := c.Orders.Create(ctx, &pb.OrderCreateRequest{Items: items})
    if err != nil {
        return "", fmt.Errorf("creating order: %w", err)
    }
    return reply.GetOrderId(), nil
}
```

## Proto Generation

- Use a shared proto repository for common service definitions
- Generate code using `buf` with language-specific plugins
- Keep generated code in a dedicated package — never edit generated files
- Version proto files (`v1`, `v2`) for backwards compatibility

## Event Key Management

```go
// Define event constants in a dedicated package
package order_event_key

type EventKey string

const (
    Created       EventKey = "order.created"
    StatusUpdated EventKey = "order.status_updated"
    Completed     EventKey = "order.completed"
    Cancelled     EventKey = "order.cancelled"
)

// Type-safe event classification
func FromEvent(raw string) (EventKey, bool) {
    switch EventKey(raw) {
    case Created, StatusUpdated, Completed, Cancelled:
        return EventKey(raw), true
    default:
        return "", false
    }
}
```

## Best Practices

- **Single shared connection** — don't create per-call connections
- **Service registry** for all connections — never hardcode addresses
- Keep dependency footprint minimal in the client library
- Use typed enums for event keys, not raw strings
- Include structured logging support
- Close connections gracefully on shutdown
- Handle transient errors with retry policies (configured at the connection level)
