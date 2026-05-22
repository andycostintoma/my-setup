---
name: go-grpc
description: "Activate when working on gRPC service definitions, protobuf schemas, interceptors, or transport layer code in Go."
license: MIT
---

# Go gRPC Service Patterns

## Architecture

gRPC is a **port** (inbound adapter) in Clean Architecture. Handlers live in the `ports/grpc/` layer and do three things:

1. Convert proto request → domain/command/query types
2. Call the application layer
3. Convert domain result → proto response

**No business logic in handlers.** They are thin translation layers.

## Handler Pattern

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

## Proto ↔ Domain Conversion

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

## Service Definition

```protobuf
service OrderService {
    rpc Get(OrderGetRequest) returns (OrderGetReply);
    rpc Create(OrderCreateRequest) returns (OrderCreateReply);
    rpc Submit(OrderSubmitRequest) returns (OrderSubmitReply);
    rpc Cancel(OrderCancelRequest) returns (OrderCancelReply);
    rpc List(OrderListRequest) returns (OrderListReply);
}
```

### Naming Convention

- Request: `[Entity][Operation]Request`
- Reply: `[Entity][Operation]Reply`
- Keep proto files versioned (`v1`, `v2`)
- Use `buf` for generation and linting

## Forward Compatibility

Always embed the unimplemented server:

```go
type OrderGrpcHandler struct {
    pb.UnimplementedOrderServiceServer
    // dependencies
}
```

## Interceptor Chain

Order matters — outermost runs first:

1. **Recovery** — panic handling, return `codes.Internal`
2. **Error mapping** — domain errors → gRPC status codes
3. **Logging** — structured request/response logging
4. **Tracing** — OpenTelemetry span creation
5. **Auth** — JWT verification, claims extraction (if applicable)

### Error Mapping Interceptor

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

## Handler Decorators

Wrap command/query handlers with logging, metrics, tracing — not in the gRPC handler itself:

```go
// Decorated at composition time, not in the handler
submitHandler := logging.NewCommandDecorator(
    command.NewSubmitOrderHandler(repo),
    logger,
)
```

This keeps handlers thin and cross-cutting concerns composable.

## Server Registration

```go
func RegisterGRPCHandlers(server *grpc.Server, app *orders.App) {
    pb.RegisterOrderServiceServer(server, NewOrderGrpcHandler(app))
}
```

## Best Practices

- Handlers do **conversion only** — no business logic, no orchestration
- Proto types **never leak** into domain or application layers
- Error mapping happens in a **single interceptor**, not per-handler
- Use `protoc-gen-validate` or manual validation at the handler level for proto field validation
- Keep handler methods short — if a handler grows, the logic probably belongs in the application layer
- Use read-only transactions for query RPCs, read-write for command RPCs (managed by repository)
- Enable gRPC reflection only in development
- Implement health checks with `grpc-health`
