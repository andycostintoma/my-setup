---
name: go-microservice
description: "Activate when building or maintaining a Go gRPC microservice that uses Clean Architecture / DDD — covers domain/application layers, the gRPC port layer, the BFF facade variant, and the client library. Skip for flat, non-layered Go projects (plain CLIs, simple REST handlers); use go-performance and use-modern-go for those concerns instead."
license: MIT
---

# Go gRPC Microservice Patterns

This skill describes **one specific stack**: a Clean-Architecture / DDD Go service
exposed over gRPC, plus the BFF facade and client-library shapes that surround it.
If a project is not layered/DDD/gRPC (e.g. a flat CLI or a simple REST service),
do **not** force these patterns — reach for `use-modern-go` and `go-performance`
instead.

The four parts below are layers of one architecture and one request lifecycle:

1. **Service core** — domain + application (this is the heart).
2. **gRPC port** — the inbound transport adapter for the service.
3. **BFF facade** — a specialized, frontend-facing service variant (no domain).
4. **Client library** — how other services call yours.

---

## 1. Service Core (Domain + Application)

### Architecture

- **Clean Architecture** with strict layer dependencies (inward only)
- **Domain-Driven Design** with rich domain models and aggregate boundaries
- **CQRS** — separate command (write) and query (read) paths
- Constructor-based dependency injection
- Repository pattern for persistence abstraction

### Project Structure

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

### Layer Responsibilities

| Layer | Does | Does NOT |
|---|---|---|
| **Domain** | Business rules, validation, entities, value objects, errors | Import infrastructure, manage transactions, orchestrate |
| **Application** | Orchestrate via `context.Context`, call repos and services | Contain business rules, manage transactions, validate |
| **Ports** | Handle transport (gRPC/HTTP/cron), convert proto ↔ domain | Contain business logic, orchestrate |
| **Adapters** | Implement repos, manage transactions, call external APIs | Contain business logic, validate, orchestrate |

### Domain Layer

#### Aggregate Root

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

#### Domain Errors

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

#### Repository Interface (Defined in Domain)

```go
// domain/repository.go
type OrderRepository interface {
    Get(ctx context.Context, id string) (*Order, error)
    Save(ctx context.Context, order *Order) error
    Update(ctx context.Context, order *Order) error
}
```

### Application Layer (CQRS)

#### Command Handler (Write Path)

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

#### Query Handler (Read Path)

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

#### Handler Decorators

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

### Dependency Injection

#### Composition Root

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

#### Three-Phase Initialization

1. **Config** — environment variables, logging, tracing
2. **Infrastructure** — database connections, external service clients
3. **Application** — compose handlers from infrastructure dependencies

### Error Handling

- All errors defined in `domain/errors.go` — centralized, not scattered
- Wrap errors with context: `fmt.Errorf("submitting order: %w", err)`
- Return early on validation failures
- Map domain errors to transport codes at the port layer (e.g., gRPC interceptor)

### Testing

- **Domain**: Pure unit tests — no mocks needed, test business logic directly
- **Application**: Mock repository interface, test orchestration
- **Integration**: Real database, test full command/query flow
- Table-driven tests for comprehensive coverage
- Test data builders for structured test setup

### Core Rules

- Domain layer has **zero infrastructure imports** — no DB, no HTTP, no proto
- Application layer uses **only `context.Context`** — no transactions, no transport types
- Transactions are **adapter concerns** — repository implementations manage them
- Commands return IDs or errors, queries return DTOs
- Constructors (`New...`) validate, `UnmarshalFromPersistence` does not
- Make implicit concepts explicit — value objects, not primitive strings
- Use ubiquitous language from the business domain

---

## 2. gRPC Port (Inbound Transport Adapter)

gRPC is a **port** (inbound adapter). Handlers live in `ports/grpc/` and do three things:

1. Convert proto request → domain/command/query types
2. Call the application layer
3. Convert domain result → proto response

**No business logic in handlers.** They are thin translation layers.

### Handler Pattern

```go
// ports/grpc/order_handler.go
type OrderGrpcHandler struct {
    pb.UnimplementedOrderServiceServer
    app *orders.App
}

func NewOrderGrpcHandler(app *orders.App) OrderGrpcHandler {
    return OrderGrpcHandler{app: app}
}

func (h OrderGrpcHandler) Submit(ctx context.Context, req *pb.OrderSubmitRequest) (*pb.OrderSubmitReply, error) {
    // 1. Convert proto → command
    cmd := command.SubmitOrder{
        OrderID: req.GetOrderId(),
    }

    // 2. Call application layer
    if err := h.app.Commands.SubmitOrder.Handle(ctx, cmd); err != nil {
        return nil, err  // Error interceptor maps to gRPC status
    }

    // 3. Return response
    return &pb.OrderSubmitReply{}, nil
}

func (h OrderGrpcHandler) Get(ctx context.Context, req *pb.OrderGetRequest) (*pb.OrderGetReply, error) {
    result, err := h.app.Queries.GetOrder.Handle(ctx, query.GetOrder{
        OrderID: req.GetOrderId(),
    })
    if err != nil {
        return nil, err
    }

    return toProtoOrderReply(result), nil
}
```

### Proto ↔ Domain Conversion

Conversion functions live in `ports/grpc/` — **never in domain or application layers**:

```go
// ports/grpc/converters.go
func toProtoOrderReply(r query.GetOrderResult) *pb.OrderGetReply {
    return &pb.OrderGetReply{
        Id:        r.ID,
        Status:    r.Status,
        ItemCount: int32(r.ItemCount),
        CreatedAt: timestamppb.New(r.CreatedAt),
    }
}

func toDomainItems(protoItems []*pb.OrderItem) []domain.OrderItem {
    items := make([]domain.OrderItem, 0, len(protoItems))
    for _, pi := range protoItems {
        items = append(items, domain.OrderItem{
            ProductID: pi.GetProductId(),
            Quantity:  int(pi.GetQuantity()),
        })
    }
    return items
}
```

### Service Definition

```protobuf
service OrderService {
    rpc Get(OrderGetRequest) returns (OrderGetReply);
    rpc Create(OrderCreateRequest) returns (OrderCreateReply);
    rpc Submit(OrderSubmitRequest) returns (OrderSubmitReply);
    rpc Cancel(OrderCancelRequest) returns (OrderCancelReply);
    rpc List(OrderListRequest) returns (OrderListReply);
}
```

Naming convention:

- Request: `[Entity][Operation]Request`
- Reply: `[Entity][Operation]Reply`
- Keep proto files versioned (`v1`, `v2`)
- Use `buf` for generation and linting

### Forward Compatibility

Always embed the unimplemented server:

```go
type OrderGrpcHandler struct {
    pb.UnimplementedOrderServiceServer
    // dependencies
}
```

### Interceptor Chain

Order matters — outermost runs first:

1. **Recovery** — panic handling, return `codes.Internal`
2. **Error mapping** — domain errors → gRPC status codes
3. **Logging** — structured request/response logging
4. **Tracing** — OpenTelemetry span creation
5. **Auth** — JWT verification, claims extraction (if applicable)

#### Error Mapping Interceptor

Map domain errors to gRPC codes centrally — not in each handler:

```go
// ports/grpc/errors.go
func errorToGRPCStatus(err error) error {
    switch {
    case errors.Is(err, domain.ErrNotFound):
        return status.Error(codes.NotFound, err.Error())
    case errors.Is(err, domain.ErrValidation):
        return status.Error(codes.InvalidArgument, err.Error())
    case errors.Is(err, domain.ErrConflict):
        return status.Error(codes.AlreadyExists, err.Error())
    default:
        return status.Error(codes.Internal, "internal error")
    }
}
```

### Server Registration

```go
func RegisterGRPCHandlers(server *grpc.Server, app *orders.App) {
    pb.RegisterOrderServiceServer(server, NewOrderGrpcHandler(app))
}
```

### gRPC Port Rules

- Handlers do **conversion only** — no business logic, no orchestration
- Proto types **never leak** into domain or application layers
- Error mapping happens in a **single interceptor**, not per-handler
- Validate proto fields at the handler level (`protoc-gen-validate` or manual)
- Keep handler methods short — if a handler grows, the logic belongs in the application layer
- Read-only transactions for query RPCs, read-write for command RPCs (managed by repository)
- Enable gRPC reflection only in development; implement health checks with `grpc-health`

---

## 3. BFF Facade (Frontend-Facing Service Variant)

A BFF service is a **facade** between the frontend and internal microservices. It is a
specialized service shape: it has the gRPC port and conversion layers above, but
**no domain/application core** — only orchestration and data transformation.

- **No business logic** — only orchestration and data transformation
- Single entry point for the frontend to access multiple backend services
- Transforms requests/responses between frontend and internal formats
- Lets frontend and backend APIs evolve independently
- Uses a **service registry** for all internal service connections (see section 4)

### Handler Pattern

```go
// ports/grpc/order_handler.go
func (h *OrderHandler) Get(ctx context.Context, req *pb.OrderGetRequest) (*pb.OrderGetReply, error) {
    claims := auth.ClaimsFromContext(ctx)

    // Convert frontend request → internal service request
    internalReq := &order_pb.OrderGetRequest{
        CompanyId: claims.CompanyID,
        OrderId:   req.GetOrderId(),
    }

    // Call internal microservice
    reply, err := h.clients.OrderService.Get(ctx, internalReq)
    if err != nil {
        return nil, err
    }

    // Convert internal response → frontend response
    return toFrontendOrderReply(reply), nil
}
```

### Authentication

```go
func (i *AuthInterceptor) authorize(ctx context.Context) (context.Context, error) {
    token := extractBearerToken(ctx)

    claims, err := i.jwt.VerifyClaims(token)
    if err != nil {
        return nil, status.Error(codes.Unauthenticated, "invalid token")
    }

    // Extract tenant context from metadata
    md, _ := metadata.FromIncomingContext(ctx)
    companyID := md.Get("company_id")[0]

    ctx = auth.SetUserID(ctx, claims.UserID)
    ctx = auth.SetCompanyID(ctx, companyID)

    return ctx, nil
}
```

### Data Transformation

Keep converters in a dedicated file within the ports layer. Compute UI-specific fields here:

```go
// ports/grpc/converters.go
func toFrontendOrderReply(internal *order_pb.OrderGetReply) *pb.OrderGetReply {
    return &pb.OrderGetReply{
        Id:            internal.GetId(),
        Status:        internal.GetStatus(),
        DisplayStatus: humanizeStatus(internal.GetStatus()),
        FormattedDate: formatDate(internal.GetCreatedAt()),
        CanEdit:       canEdit(internal),
        ShowAlerts:    hasActiveAlerts(internal),
        StatusColor:   statusColor(internal.GetStatus()),
    }
}
```

Use hierarchical proto naming for view contexts; include pre-computed UI fields
(`display_status`, `formatted_date`, `can_edit`) and paginated/filtered list requests.

### Stats Aggregation

Use `errgroup` to fan out to independent internal services in parallel:

```go
func (h *StatsHandler) GetDashboardStats(ctx context.Context, req *pb.StatsRequest) (*pb.StatsReply, error) {
    claims := auth.ClaimsFromContext(ctx)
    eg, childCtx := errgroup.WithContext(ctx)

    var orderStats *order_pb.StatsReply
    eg.Go(func() error {
        var err error
        orderStats, err = h.clients.OrderService.GetStats(childCtx, &order_pb.StatsRequest{
            CompanyId: claims.CompanyID,
            DateRange: toInternalDateRange(req.GetDateRange()),
        })
        return err
    })

    var shippingStats *shipping_pb.StatsReply
    eg.Go(func() error {
        var err error
        shippingStats, err = h.clients.ShippingService.GetStats(childCtx, &shipping_pb.StatsRequest{
            CompanyId: claims.CompanyID,
            DateRange: toInternalDateRange(req.GetDateRange()),
        })
        return err
    })

    if err := eg.Wait(); err != nil {
        return nil, err
    }

    return &pb.StatsReply{
        TotalOrders:    orderStats.GetTotal(),
        TotalShipments: shippingStats.GetTotal(),
        Combined:       calculateCombined(orderStats, shippingStats),
    }, nil
}
```

### Bulk Operations

Collect per-item results and report success/failure counts rather than failing the whole batch:

```go
func (h *OrderHandler) BulkStatusUpdate(ctx context.Context, req *pb.BulkUpdateRequest) (*pb.BulkUpdateReply, error) {
    results := make([]*pb.UpdateResult, 0, len(req.GetIds()))
    for _, id := range req.GetIds() {
        _, err := h.clients.OrderService.UpdateStatus(ctx, &order_pb.StatusUpdateRequest{
            OrderId:   id,
            NewStatus: req.GetNewStatus(),
        })
        results = append(results, &pb.UpdateResult{Id: id, Error: errorMessage(err)})
    }
    return &pb.BulkUpdateReply{
        Results:      results,
        SuccessCount: countSuccesses(results),
        FailureCount: countFailures(results),
    }, nil
}
```

### BFF Rules

- **Never implement business logic** — delegate everything to internal services
- Validate and sanitize all frontend input
- Use `errgroup` for parallel calls to independent internal services
- Handle partial failures gracefully (some services may fail while others succeed)
- Cache aggregated data when appropriate
- Provide user-friendly error messages — never expose internal service details
- Use field masks to fetch only required data from internal services
- Use a service registry for all internal connections — never hardcode addresses

---

## 4. Client Library (Consuming the Service)

How other services call yours: a **facade** with a single entry point per service,
sharing one gRPC connection and resolving addresses through a **service registry**.

### Service Registry

Use a centralized registry instead of manual `grpc.NewClient`:

```go
conn, err := registry.NewConn(registry.OrderService, &registry.Options{
    Log: logger,
    ENV: envVar,
})
if err != nil {
    return fmt.Errorf("connecting to order service: %w", err)
}
client := pb.NewOrderServiceClient(conn)
```

The registry handles service discovery, credential management (TLS/xDS in prod,
insecure in dev), connection pooling, and environment awareness.

```go
// DON'T — hardcoded, no discovery, no credential management
conn, err := grpc.NewClient("localhost:50051",
    grpc.WithTransportCredentials(insecure.NewCredentials()))

// DO — service registry handles everything
conn, err := registry.NewConn(registry.OrderService, opts)
```

### Client Facade

Share one connection across all generated clients:

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

### Options Pattern

```go
type Options struct {
    Logger *slog.Logger
    ENV    string  // "local", "dev", "staging", "prod"
}
```

Support development (insecure credentials) and production (TLS/xDS) via environment-aware options.

### Wrapper Methods

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

### Proto Generation

- Use a shared proto repository for common service definitions
- Generate code with `buf` and language-specific plugins
- Keep generated code in a dedicated package — never edit generated files
- Version proto files (`v1`, `v2`) for backwards compatibility

### Event Key Management

```go
package order_event_key

type EventKey string

const (
    Created       EventKey = "order.created"
    StatusUpdated EventKey = "order.status_updated"
    Completed     EventKey = "order.completed"
    Cancelled     EventKey = "order.cancelled"
)

func FromEvent(raw string) (EventKey, bool) {
    switch EventKey(raw) {
    case Created, StatusUpdated, Completed, Cancelled:
        return EventKey(raw), true
    default:
        return "", false
    }
}
```

### Client Library Rules

- **Single shared connection** — don't create per-call connections
- **Service registry** for all connections — never hardcode addresses
- Keep the client library's dependency footprint minimal
- Use typed enums for event keys, not raw strings
- Include structured logging support
- Close connections gracefully on shutdown
- Handle transient errors with retry policies (configured at the connection level)
