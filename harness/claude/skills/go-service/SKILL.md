---
name: go-service
description: "Activate when working on Go backend microservices — covers clean architecture, service operation pattern, dependency injection, domain-driven design, and business logic organization."
license: MIT
---

# Go Backend Microservice Patterns

## Architecture

- **Clean Architecture** with strict layer dependencies (inward only)
- **Domain-Driven Design** with rich domain models and aggregate boundaries
- **CQRS** — separate command (write) and query (read) paths
- Constructor-based dependency injection
- Repository pattern for persistence abstraction

## Project Structure

```
/service-name
├── cmd/server/main.go            # Entry point, wiring
├── internal/<domain>/
│   ├── domain/                   # Entities, value objects, errors, interfaces
│   │   ├── <aggregate>.go        # Aggregate root with business logic
│   │   ├── errors.go             # All domain errors (sentinel + typed)
│   │   └── repository.go         # Repository interface (defined here, implemented in adapters)
│   ├── app/                      # Application layer — orchestration only
│   │   ├── command/              # Write operations (Create, Update, Cancel, etc.)
│   │   └── query/                # Read operations (Get, List, Retrieve, etc.)
│   ├── ports/                    # Inbound adapters (transport layer)
│   │   ├── grpc/                 # gRPC handlers, proto ↔ domain conversion
│   │   └── cron/                 # Scheduled task handlers
│   └── adapters/                 # Outbound adapters (infrastructure)
│       ├── <database>/           # Repository implementations
│       └── <external_service>/   # External service clients
└── deployments/                  # K8s, Docker, CI configs
```

## Layer Responsibilities

| Layer | Does | Does NOT |
|---|---|---|
| **Domain** | Business rules, validation, entities, value objects, errors | Import infrastructure, manage transactions, orchestrate |
| **Application** | Orchestrate via `context.Context`, call repos and services | Contain business rules, manage transactions, validate |
| **Ports** | Handle transport (gRPC/HTTP/cron), convert proto ↔ domain | Contain business logic, orchestrate |
| **Adapters** | Implement repos, manage transactions, call external APIs | Contain business logic, validate, orchestrate |

## Domain Layer

### Aggregate Root

```go
// domain/order.go
type Order struct {
    id         string
    status     Status
    items      []OrderItem
    createdAt  time.Time
    updatedAt  time.Time
}

// Constructor with validation — the only way to create
func NewOrder(id string, items []OrderItem) (*Order, error) {
    if id == "" {
        return nil, ErrOrderIDRequired
    }
    if len(items) == 0 {
        return nil, ErrOrderItemsRequired
    }
    return &Order{
        id:        id,
        status:    StatusDraft,
        items:     items,
        createdAt: time.Now().UTC(),
        updatedAt: time.Now().UTC(),
    }, nil
}

// Business logic lives ON the entity
func (o *Order) Submit() error {
    if o.status != StatusDraft {
        return ErrCannotSubmitNonDraft
    }
    o.status = StatusSubmitted
    o.updatedAt = time.Now().UTC()
    return nil
}

// Persistence rehydration — bypasses validation (data already valid in DB)
func UnmarshalOrderFromPersistence(id string, status Status, items []OrderItem, createdAt, updatedAt time.Time) *Order {
    return &Order{
        id: id, status: status, items: items,
        createdAt: createdAt, updatedAt: updatedAt,
    }
}
```

### Domain Errors

All errors live in `domain/errors.go`. Use typed/sentinel errors, never `errors.New` elsewhere:

```go
// domain/errors.go
var (
    ErrOrderIDRequired      = errors.New("order ID is required")
    ErrOrderItemsRequired   = errors.New("order must have at least one item")
    ErrCannotSubmitNonDraft  = errors.New("only draft orders can be submitted")
    ErrOrderNotFound         = errors.New("order not found")
)
```

### Repository Interface (Defined in Domain)

```go
// domain/repository.go
type OrderRepository interface {
    Get(ctx context.Context, id string) (*Order, error)
    Save(ctx context.Context, order *Order) error
    Update(ctx context.Context, order *Order) error
}
```

## Application Layer (CQRS)

### Command Handler (Write Path)

```go
// app/command/submit_order.go
type SubmitOrder struct {
    OrderID string
}

type SubmitOrderHandler struct {
    repo domain.OrderRepository
}

func NewSubmitOrderHandler(repo domain.OrderRepository) SubmitOrderHandler {
    return SubmitOrderHandler{repo: repo}
}

func (h SubmitOrderHandler) Handle(ctx context.Context, cmd SubmitOrder) error {
    order, err := h.repo.Get(ctx, cmd.OrderID)
    if err != nil {
        return fmt.Errorf("getting order: %w", err)
    }

    if err := order.Submit(); err != nil {
        return fmt.Errorf("submitting order: %w", err)
    }

    if err := h.repo.Update(ctx, order); err != nil {
        return fmt.Errorf("updating order: %w", err)
    }

    return nil
}
```

### Query Handler (Read Path)

```go
// app/query/get_order.go
type GetOrder struct {
    OrderID string
}

type GetOrderResult struct {
    ID        string
    Status    string
    ItemCount int
    CreatedAt time.Time
}

type GetOrderHandler struct {
    repo domain.OrderRepository
}

func (h GetOrderHandler) Handle(ctx context.Context, q GetOrder) (GetOrderResult, error) {
    order, err := h.repo.Get(ctx, q.OrderID)
    if err != nil {
        return GetOrderResult{}, fmt.Errorf("getting order: %w", err)
    }

    return GetOrderResult{
        ID:        order.ID(),
        Status:    order.Status().String(),
        ItemCount: len(order.Items()),
        CreatedAt: order.CreatedAt(),
    }, nil
}
```

### Handler Decorators

Wrap handlers with cross-cutting concerns (logging, metrics, tracing):

```go
// app/command/decorator.go
type CommandHandler[C any] interface {
    Handle(ctx context.Context, cmd C) error
}

type loggingDecorator[C any] struct {
    base   CommandHandler[C]
    logger *slog.Logger
}

func (d loggingDecorator[C]) Handle(ctx context.Context, cmd C) error {
    d.logger.Info("executing command", "command", fmt.Sprintf("%T", cmd))
    err := d.base.Handle(ctx, cmd)
    if err != nil {
        d.logger.Error("command failed", "command", fmt.Sprintf("%T", cmd), "error", err)
    }
    return err
}
```

## Dependency Injection

### Composition Root

Wire everything in a single place — typically `internal/<domain>/<domain>.go`:

```go
// internal/orders/orders.go
type App struct {
    Commands Commands
    Queries  Queries
}

type Commands struct {
    SubmitOrder command.SubmitOrderHandler
    CancelOrder command.CancelOrderHandler
}

type Queries struct {
    GetOrder  query.GetOrderHandler
    ListOrders query.ListOrdersHandler
}

func NewApp(repo domain.OrderRepository, logger *slog.Logger) App {
    return App{
        Commands: Commands{
            SubmitOrder: command.NewSubmitOrderHandler(repo),
            CancelOrder: command.NewCancelOrderHandler(repo),
        },
        Queries: Queries{
            GetOrder:   query.NewGetOrderHandler(repo),
            ListOrders: query.NewListOrdersHandler(repo),
        },
    }
}
```

### Three-Phase Initialization

1. **Config** — environment variables, logging, tracing
2. **Infrastructure** — database connections, external service clients
3. **Application** — compose handlers from infrastructure dependencies

## Error Handling

- All errors defined in `domain/errors.go` — centralized, not scattered
- Wrap errors with context: `fmt.Errorf("submitting order: %w", err)`
- Return early on validation failures
- Map domain errors to transport codes at the port layer (e.g., gRPC interceptor)

## Testing

- **Domain**: Pure unit tests — no mocks needed, test business logic directly
- **Application**: Mock repository interface, test orchestration
- **Integration**: Real database, test full command/query flow
- Table-driven tests for comprehensive coverage
- Test data builders for structured test setup

## Key Rules

- Domain layer has **zero infrastructure imports** — no DB, no HTTP, no proto
- Application layer uses **only `context.Context`** — no transactions, no transport types
- Transactions are **adapter concerns** — repository implementations manage them
- Commands return IDs or errors, queries return DTOs
- Constructors (`New...`) validate, `UnmarshalFromPersistence` does not
- Make implicit concepts explicit — value objects, not primitive strings
- Use ubiquitous language from the business domain
