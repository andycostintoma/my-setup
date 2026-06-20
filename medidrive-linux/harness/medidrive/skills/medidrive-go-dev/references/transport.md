# Writing Transport Layer (gRPC Handlers)

The transport layer lives in `internal/transport/grpc/<area>/`. It handles proto mapping, error translation, and delegates to usecases.

## What Goes in Transport

- Proto imports (`pb` packages) — ONLY here, nowhere else
- `toProto()` / `fromProto()` mapper functions
- gRPC error code mapping
- Request validation (transport-level, not business)
- Handler structs that call usecases

## Handler Structure

```go
package settlement

import (
    "context"

    pb "github.com/acme/proto/settlement_pb"
    "internal/app/settlement/usecases/process_settlement"
    "internal/app/settlement/queries/settlement_get"
    "google.golang.org/grpc/codes"
    "google.golang.org/grpc/status"
)

type Handler struct {
    commands Commands
    queries  Queries
}

type Commands struct {
    ProcessSettlement *process_settlement.Interactor
}

type Queries struct {
    GetSettlement *settlement_get.Query
}

func NewHandler(cmds Commands, qrs Queries) *Handler {
    return &Handler{commands: cmds, queries: qrs}
}
```

## Handler Methods

Handlers do THREE things only: map request → call usecase → map response/error.

```go
func (h *Handler) ProcessSettlement(ctx context.Context, req *pb.ProcessRequest) (*pb.ProcessResponse, error) {
    // 1. Map proto → usecase request
    ucReq := fromProtoProcessRequest(req)

    // 2. Call usecase
    err := h.commands.ProcessSettlement.Execute(ctx, ucReq)
    if err != nil {
        return nil, mapError(err)  // 3. Map error to gRPC status
    }

    return &pb.ProcessResponse{}, nil
}
```

## Mapper Functions

```go
func fromProtoProcessRequest(req *pb.ProcessRequest) *process_settlement.Request {
    return &process_settlement.Request{
        SettlementID: req.GetSettlementId(),
        CompanyID:    req.GetCompanyId(),
    }
}

func toProtoSettlement(s *domain.Settlement) *pb.Settlement {
    return &pb.Settlement{
        Id:          s.ID().String(),
        Status:      string(s.Status()),
        TotalAmount: s.TotalAmount().FloatString(2),
    }
}
```

## Error Mapping

```go
func mapError(err error) error {
    switch {
    case errors.Is(err, domain.ErrInvalidTransition):
        return status.Errorf(codes.FailedPrecondition, err.Error())
    case errors.Is(err, usecases.ErrNotFound):
        return status.Errorf(codes.NotFound, err.Error())
    case errors.Is(err, usecases.ErrValidationFailed):
        return status.Errorf(codes.InvalidArgument, err.Error())
    default:
        return status.Errorf(codes.Internal, "internal error")
    }
}
```

## Key Rules

- **Proto imports** (`pb`) — ONLY in transport, never in domain/usecases/repo
- **toProto/fromProto** — ONLY in transport
- **Handlers NEVER apply plans** — that's the usecase's job
- **No business logic** in handlers — they just map and delegate
- **CQRS**: separate commands (usecases) from queries in the handler
- **Error mapping**: domain/app errors → appropriate gRPC codes

## Protobuf Enum Usage

```go
// ✅ Use StringVal() for string value
status := pb.Order_Status_ACTIVE.StringVal()  // "ACTIVE"

// ❌ DON'T use String() — it's a decorator
status := pb.Order_Status_ACTIVE.String()  // "Order_Status_ACTIVE" ← wrong

// ✅ Use StringTo<EnumName>() for conversion
pbStatus := pb.StringToOrderStatus(row.Status)
```
