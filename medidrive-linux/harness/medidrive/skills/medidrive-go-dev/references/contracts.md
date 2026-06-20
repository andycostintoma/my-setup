# Writing Contracts (Port Interfaces)

Contracts define the boundaries between layers. They live in `internal/app/<area>/contracts/`.

## How to Write Contracts

### Repository contract

```go
package contracts

import (
    "context"
    "internal/app/order/domain"
)

// OrderRepo provides persistence for Order aggregates.
type OrderRepo interface {
    Retrieve(ctx context.Context, id string) (*domain.Order, error)
    UpdateMut(order *domain.Order) any   // Returns mutation, never applies
    CreateMut(order *domain.Order) any   // Returns mutation for new entities
}
```

### Infrastructure contracts (external services)

```go
type ExternalSender interface {
    Send(ctx context.Context, dest, payload string) (string, error)
}

type Clock interface {
    Now() time.Time
}

type Logger interface {
    Infof(format string, args ...any)
    Warnf(format string, args ...any)
    Errorf(format string, args ...any)
}
```

### Usecase contract (optional, for handler → usecase boundary)

```go
// In usecases/activate_order/types.go
package activate_order

type Request struct {
    OrderID   string
    CompanyID string
}

type Handler interface {
    Execute(ctx context.Context, req *Request) error
}

// In interactor.go:
// var _ Handler = (*Interactor)(nil)
```

## Rules

- Keep interfaces tiny: 1–3 methods each
- Define at the point of use (in contracts/ or next to the usecase)
- Only import `domain` and standard library — never concrete implementations
- Compile-time checks go in the implementing package, not in contracts
- Use `any` for mutation return types to keep contracts DB-agnostic
